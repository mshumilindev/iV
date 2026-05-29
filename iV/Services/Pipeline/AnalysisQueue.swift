import Foundation
import IOKit.ps

enum AnalysisJobPriority: Int, Comparable, Sendable {
    case editorCritical = 0
    case paragraphMechanical = 1
    case paragraphWindow = 2
    case sceneMechanical = 3
    case selectedLLM = 4
    case chapterMechanical = 5
    case chapterLLM = 6
    case background = 7

    static func < (lhs: AnalysisJobPriority, rhs: AnalysisJobPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AnalysisJob: Identifiable, Sendable {
    let id: UUID
    let priority: AnalysisJobPriority
    let scopeKey: String
    let isLLM: Bool
    let label: String
    let work: @Sendable () async -> Void
}

struct AnalysisQueueStatus: Sendable, Equatable {
    var pendingCount: Int
    var isRunningLLM: Bool
    var isPaused: Bool
    var pauseReason: String?
    var lastCompletedLabel: String?
}

enum ScopeResolver {
    static func expansionOrder(startingAt scope: RuleScope) -> [RuleScope] {
        [.selection, .sentence, .paragraph, .paragraphWindow, .scene, .previousSceneCurrentScene,
         .chapterSection, .chapter, .previousChapterCurrentChapter, .document, .project]
    }
}

enum SystemPowerState: Sendable {
    case onBattery
    case pluggedIn
    case unknown
}

enum PerformancePolicyService {
    static func mechanicalDebounce(mode: PerformanceMode) -> Duration {
        switch mode {
        case .quiet, .balanced: .milliseconds(750)
        case .intensive: .milliseconds(500)
        case .manualOnly: .seconds(3600)
        }
    }

    static func llmDebounce(mode: PerformanceMode) -> Duration {
        switch mode {
        case .quiet, .manualOnly: .seconds(3600)
        case .balanced: .milliseconds(5000)
        case .intensive: .milliseconds(3000)
        }
    }

    static func allowsLLMBackground(mode: PerformanceMode) -> Bool {
        mode == .intensive || mode == .balanced
    }

    static func allowsLLMWatch(mode: PerformanceMode, ollamaEnabled: Bool) -> Bool {
        ollamaEnabled && mode != .quiet && mode != .manualOnly
    }

    static func currentPowerState() -> SystemPowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let state = desc[kIOPSPowerSourceStateKey] as? String else {
            return .unknown
        }
        if state == kIOPSBatteryPowerValue { return .onBattery }
        if state == kIOPSACPowerValue { return .pluggedIn }
        return .unknown
    }

    static func shouldPauseLLM(mode: PerformanceMode) -> (Bool, String?) {
        let power = currentPowerState()
        if power == .onBattery && mode == .intensive {
            return (true, "On battery — LLM paused")
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return (true, "Low Power Mode — LLM paused")
        }
        return (false, nil)
    }
}

@MainActor
final class AnalysisQueue {
    private var pending: [AnalysisJob] = []
    private var runningLLM: Task<Void, Never>?
    private var isTyping = false
    var maxConcurrentLLM = 1
    private(set) var status = AnalysisQueueStatus(pendingCount: 0, isRunningLLM: false, isPaused: false)

    func markTyping(_ typing: Bool) {
        isTyping = typing
        if typing {
            runningLLM?.cancel()
            runningLLM = nil
            cancelAllLLM()
        }
        refreshStatus()
    }

    func enqueue(_ job: AnalysisJob) {
        pending.removeAll { $0.scopeKey == job.scopeKey && $0.isLLM == job.isLLM }
        pending.append(job)
        pending.sort { $0.priority < $1.priority }
        refreshStatus()
        processNext()
    }

    func cancelAllLLM() {
        runningLLM?.cancel()
        runningLLM = nil
        pending.removeAll { $0.isLLM }
        refreshStatus()
    }

    func setPaused(_ paused: Bool, reason: String?) {
        status.isPaused = paused
        status.pauseReason = reason
        if paused { cancelAllLLM() }
        refreshStatus()
    }

    private func refreshStatus() {
        status.pendingCount = pending.count
        status.isRunningLLM = runningLLM != nil
    }

    private func processNext() {
        guard !status.isPaused else { return }
        guard let next = pending.first else {
            refreshStatus()
            return
        }
        if next.isLLM {
            guard !isTyping, runningLLM == nil else { return }
            pending.removeFirst()
            refreshStatus()
            runningLLM = Task {
                await next.work()
                status.lastCompletedLabel = next.label
                runningLLM = nil
                refreshStatus()
                processNext()
            }
        } else {
            pending.removeFirst()
            refreshStatus()
            Task {
                await next.work()
                status.lastCompletedLabel = next.label
                processNext()
            }
        }
    }
}

enum ChapterSplitAnalyzer {
    static func suggestSplits(index: DocumentIndex) -> [ChapterSplitSuggestion] {
        index.paragraphs.enumerated().compactMap { _, indexed -> ChapterSplitSuggestion? in
            let text = indexed.paragraph.text.lowercased()
            let signals = ["later", "next day", "meanwhile", "наступного дня", "тим часом", "***"].filter { text.contains($0) }
            guard !signals.isEmpty else { return nil }
            return ChapterSplitSuggestion(
                id: UUID(),
                paragraphID: indexed.paragraph.id,
                confidence: text.contains("***") ? 0.8 : 0.6,
                reason: "Possible break: \(signals.joined(separator: ", "))",
                risk: .medium,
                splitType: text.contains("***") ? .hardChapterBreak : .softSectionBreak
            )
        }
    }
}

enum ManualReviewCalculator {
    static func status(
        diagnostics: [Diagnostic],
        proposals: [ChangeProposal],
        passResults: [PipelinePassResult] = [],
        llmPassesEnabled: Bool = true
    ) -> ManualReviewStatus {
        let open = diagnostics.filter { $0.status == .open && !$0.isStale }
        var blockers: [String] = []
        let blocking = open.filter { $0.severity == .blocking }
        if !blocking.isEmpty {
            blockers.append("\(blocking.count) blocking diagnostic\(blocking.count == 1 ? "" : "s")")
        }
        let highRisk = proposals.filter { $0.status == .pending && $0.riskLevel == .high }
        if !highRisk.isEmpty {
            blockers.append("\(highRisk.count) high-risk pending proposal\(highRisk.count == 1 ? "" : "s")")
        }
        let llmFailed = passResults.contains { $0.llmStatus == .failed || ($0.mode == .llm && $0.status == .failed) }
        if llmFailed {
            blockers.append("LLM pass failure(s) need review")
        }
        if llmPassesEnabled {
            let llmRequiredUnavailable = passResults.contains {
                ($0.mode == .llm && $0.status == .unavailable)
                    || ($0.mode == .hybrid && $0.llmStatus == .unavailable)
            }
            if llmRequiredUnavailable {
                blockers.append("Required LLM passes unavailable (Ollama)")
            }
        }
        let note = blockers.isEmpty ? nil : blockers.joined(separator: "; ")
        return ManualReviewStatus(
            isReady: blockers.isEmpty,
            blockingIssues: blocking.count,
            errors: open.filter { $0.severity == .error }.count,
            warnings: open.filter { $0.severity == .warning }.count,
            styleRisks: open.filter { $0.scope == .paragraph || $0.scope == .sentence }.count,
            canonRisks: open.filter { $0.title.localizedCaseInsensitiveContains("canon") }.count,
            logicRisks: open.filter { $0.scope == .scene || $0.scope == .chapter }.count,
            aiPatternRisks: open.filter { $0.source == .llm || $0.title.localizedCaseInsensitiveContains("AI") }.count,
            pendingProposals: proposals.filter { $0.status == .pending }.count,
            readinessNote: note
        )
    }
}
