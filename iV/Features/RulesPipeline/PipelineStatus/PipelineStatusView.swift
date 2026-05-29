import SwiftUI

struct PipelineStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var pendingSplit: ChapterSplitSuggestion?

    var body: some View {
        List {
            Section("Manual Review") {
                let status = appState.manualReview
                LabeledContent("Ready", value: status.isReady ? "Yes" : "No")
                if let note = status.readinessNote, !status.isReady {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(IVColor.diagnosticWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Blocking", value: "\(status.blockingIssues)")
                LabeledContent("Errors", value: "\(status.errors)")
                LabeledContent("Warnings", value: "\(status.warnings)")
                LabeledContent("Pending proposals", value: "\(status.pendingProposals)")
            }
            Section("Analysis queue") {
                LabeledContent("Pending jobs", value: "\(appState.queueStatus.pendingCount)")
                LabeledContent("LLM running", value: appState.queueStatus.isRunningLLM ? "Yes" : "No")
                if let label = appState.queueStatus.lastCompletedLabel {
                    LabeledContent("Last job", value: label)
                }
                if appState.analysisQueuePaused, let reason = appState.analysisQueuePauseReason {
                    Text(reason).font(.caption).foregroundStyle(IVColor.diagnosticWarning)
                }
            }
            Section("Passes") {
                if appState.pipelinePassResults.isEmpty {
                    Text("No pipeline run yet").ivSecondaryLabel()
                }
                ForEach(appState.pipelinePassResults, id: \.id) { pass in
                    HStack(alignment: .top) {
                        Image(systemName: icon(for: pass.status))
                            .foregroundStyle(passIconColor(pass.status))
                            .ivFireflyBreathing(active: pass.status == .running)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pass.name).foregroundStyle(IVColor.chromePrimary)
                            Text(passStatusLine(pass)).ivMutedCaption()
                            if let det = pass.deterministicStatus, pass.mode == .hybrid {
                                Text("Mechanical: \(det.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(IVColor.chromeTertiary)
                            }
                            if let llm = pass.llmStatus {
                                Text("LLM: \(llm.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(llmPhaseColor(llm))
                            }
                            if let reason = pass.failureReason {
                                Text(reason).font(.caption2).foregroundStyle(IVColor.diagnosticError)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Text("\(pass.diagnosticsCreated)d / \(pass.proposalsCreated)p")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            if !appState.analysisRuns.isEmpty {
                Section("Run history") {
                    ForEach(appState.analysisRuns.suffix(5).reversed()) { run in
                        VStack(alignment: .leading) {
                            Text(run.pipelineID).font(.caption.weight(.semibold))
                            Text("\(run.status.rawValue) · \(run.startedAt, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(IVColor.chromeTertiary)
                        }
                    }
                }
            }
            if !appState.chapterSplitSuggestions.isEmpty {
                Section("Chapter splits") {
                    ForEach(appState.chapterSplitSuggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.reason).font(.caption)
                            Text(suggestion.splitType.rawValue).font(.caption2).foregroundStyle(IVColor.chromeTertiary)
                            Button("Create split proposal…") {
                                pendingSplit = suggestion
                            }
                            .buttonStyle(.ivGhost)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .ivInspectorList()
        .confirmationDialog("Create chapter split proposal?", isPresented: Binding(
            get: { pendingSplit != nil },
            set: { if !$0 { pendingSplit = nil } }
        ), titleVisibility: .visible) {
            Button("Create proposal", role: .destructive) {
                if let s = pendingSplit { appState.createChapterSplitProposal(s) }
                pendingSplit = nil
            }
            Button("Cancel", role: .cancel) { pendingSplit = nil }
        } message: {
            Text("Adds structural markers to the manuscript via a reviewable proposal — not applied immediately.")
        }
    }

    private func passStatusLine(_ pass: PipelinePassResult) -> String {
        switch pass.mode {
        case .hybrid:
            if pass.llmStatus == .unavailable || pass.llmStatus == .skipped {
                return "Completed (mechanical only)"
            }
            return pass.status.rawValue
        default:
            return pass.status.rawValue
        }
    }

    private func icon(for status: PipelinePassStatus) -> String {
        switch status {
        case .pending: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .skipped: "minus.circle"
        case .unavailable: "slash.circle"
        }
    }

    private func passIconColor(_ status: PipelinePassStatus) -> Color {
        switch status {
        case .pending: IVColor.chromeTertiary
        case .running: IVColor.ivySoft
        case .completed: IVColor.diagnosticSuccess
        case .failed: IVColor.diagnosticError
        case .skipped: IVColor.chromeTertiary
        case .unavailable: IVColor.diagnosticWarning
        }
    }

    private func llmPhaseColor(_ status: PipelinePassStatus) -> Color {
        switch status {
        case .unavailable, .failed: IVColor.diagnosticWarning
        case .skipped: IVColor.chromeTertiary
        default: IVColor.chromeSecondary
        }
    }
}
