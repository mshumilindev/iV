import Foundation

enum DocumentType: String, Codable, CaseIterable, Sendable {
    case manuscript, notes, canon, rules
}

enum DocumentSaveState: String, Sendable {
    case saved
    case unsaved
    case saving
    case saveError
}

enum KeepAlivePolicy: String, Codable, CaseIterable, Sendable {
    case balanced, quiet, intensive, manual
}

enum EditRuleCategory: String, Codable, CaseIterable, Sendable {
    case minimumGate, coreProse, styleLineControl, dialogue, characterVoice
    case worldInformation, atmosphereSensory, actionAftermath, canonLanguage
    case causalityPOVLogic, custom

    var displayName: String {
        switch self {
        case .minimumGate: "Minimum gate"
        case .coreProse: "Core prose"
        case .styleLineControl: "Style & line"
        case .dialogue: "Dialogue"
        case .characterVoice: "Character voice"
        case .worldInformation: "World & information"
        case .atmosphereSensory: "Atmosphere & sensory"
        case .actionAftermath: "Action & aftermath"
        case .canonLanguage: "Canon & language"
        case .causalityPOVLogic: "Causality & POV"
        case .custom: "Custom"
        }
    }
}

enum EditRuleFileSource: String, Sendable {
    case bundled, project, development
}


enum RuleSeverity: String, Codable, CaseIterable, Sendable, Comparable {
    case info, warning, error, blocking

    static func < (lhs: RuleSeverity, rhs: RuleSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .error: 2
        case .blocking: 3
        }
    }
}

enum RuleScope: String, Codable, CaseIterable, Sendable {
    case selection, sentence, paragraph, paragraphWindow, scene, previousSceneCurrentScene
    case chapterSection, chapter, previousChapterCurrentChapter, document, project
}

/// Suggested roles for installed Ollama models (user-assigned; not enforced as truth).
enum ModelRole: String, Codable, CaseIterable, Sendable {
    case generalReasoning
    case multilingual
    case proseAnalysis
    case summarization
    case embeddings
    case fastUtility
    case heavyReasoning
    case experimental
}

enum FixLevel: String, Codable, Sendable {
    case safeAutoFix, suggestedFix, humanOnly
}

enum DetectionMode: String, Codable, Sendable {
    case deterministic, llm, hybrid
}

enum DiagnosticSource: String, Codable, Sendable {
    case deterministic, llm, pipeline
}

enum DiagnosticStatus: String, Codable, Sendable {
    case open, accepted, rejected, ignored, resolved, stale
}

enum CanonEntityType: String, Codable, CaseIterable, Sendable {
    case character, location, term, institution, magicSystem
    case timelineEvent, object, relationship
}

enum MemoryScope: String, Codable, Sendable {
    case scene, chapter, document, project
}

enum AnalysisRunStatus: String, Codable, Sendable {
    case pending, running, completed, failed, cancelled
}

enum ChangeProposalSource: String, Codable, Sendable {
    case deterministic, llm, pipeline, sceneExpansion, chapterSplit
}

enum ChangeProposalStatus: String, Codable, Sendable {
    case pending, accepted, rejected, edited, ignored
}

enum RiskLevel: String, Codable, Sendable {
    case low, medium, high
}

enum PipelinePassMode: String, Codable, Sendable {
    case deterministic, llm, hybrid
}

enum PipelinePassStatus: String, Codable, Sendable {
    case pending, running, completed, failed, skipped, unavailable
}

enum PerformanceMode: String, Codable, CaseIterable, Sendable {
    case quiet, balanced, intensive, manualOnly
}

enum LocalAIBackend: String, Codable, CaseIterable, Sendable {
    case ollama, coreML, mlx, llamaCpp, appleFoundationModels, disabled
}

enum DiffDisplayMode: String, Codable, Sendable {
    case read, lightHighlight, fullDiff
}

enum SplitSuggestionType: String, Codable, Sendable {
    case softSectionBreak, hardChapterBreak, noSplit
}

enum AppNavigation: Hashable, Sendable {
    case library
    case projectOverview(UUID)
    case workspace(UUID)
}
