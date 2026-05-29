import Foundation

/// Routes analysis tasks to the correct model/backend and execution mode.
/// See `docs/PRODUCT_SPEC.md` — Local model routing & task scheduling.
@MainActor
protocol LocalModelRouter: AnyObject {
    func route(_ task: LocalModelTask) -> LocalModelRouteDecision
}

enum LocalModelTask: String, Sendable {
    case mechanicalLint
    case safeAutoFix
    case ruleParsing
    case paragraphMechanical
    case paragraphLLM
    case transitionLLM
    case sceneLogic
    case dialogue
    case atmosphere
    case rewriteProposal
    case sceneExpansion
    case chapterSplit
    case chapterEscalation
    case documentProjectCheck
    case summary
    case canonExtraction
    case embeddingUpdate
    case semanticRetrieval
}

struct LocalModelRouteDecision: Sendable {
    var backend: LocalAIBackend
    var modelName: String?
    var execution: TaskExecutionMode
    var skipReason: String?

    enum TaskExecutionMode: Sendable {
        case synchronous
        case asyncQueued
        case skip
        case mechanicalOnly
    }

    static let mechanicalOnly = LocalModelRouteDecision(
        backend: .disabled,
        modelName: nil,
        execution: .mechanicalOnly,
        skipReason: nil
    )
}

/// Default router — conservative; one LLM at a time; respects performance mode.
@MainActor
final class DefaultLocalModelRouter: LocalModelRouter {
    private let settings: () -> ModelSettings  // use project.ollamaSettings.resolvedModelSettings
    private let performanceMode: () -> PerformanceMode
    private let ollamaEnabled: () -> Bool

    init(
        settings: @escaping () -> ModelSettings,
        performanceMode: @escaping () -> PerformanceMode,
        ollamaEnabled: @escaping () -> Bool
    ) {
        self.settings = settings
        self.performanceMode = performanceMode
        self.ollamaEnabled = ollamaEnabled
    }

    func route(_ task: LocalModelTask) -> LocalModelRouteDecision {
        switch task {
        case .mechanicalLint, .safeAutoFix, .ruleParsing, .paragraphMechanical:
            return .mechanicalOnly
        case .embeddingUpdate, .semanticRetrieval:
            let s = settings()
            guard s.allowEmbeddings, !s.embeddingModelName.isEmpty, ollamaEnabled() else {
                return LocalModelRouteDecision(
                    backend: .disabled,
                    modelName: nil,
                    execution: task == .semanticRetrieval ? .mechanicalOnly : .skip,
                    skipReason: "Embeddings disabled"
                )
            }
            return LocalModelRouteDecision(
                backend: .ollama,
                modelName: s.embeddingModelName,
                execution: .asyncQueued,
                skipReason: nil
            )
        default:
            guard ollamaEnabled() else {
                return LocalModelRouteDecision(
                    backend: .disabled,
                    modelName: nil,
                    execution: .skip,
                    skipReason: "Ollama disabled"
                )
            }
            if performanceMode() == .quiet, !isUserTriggered(task) {
                return LocalModelRouteDecision(
                    backend: .disabled,
                    modelName: nil,
                    execution: .skip,
                    skipReason: "Quiet mode"
                )
            }
            if performanceMode() == .manualOnly, !isUserTriggered(task) {
                return LocalModelRouteDecision(
                    backend: .disabled,
                    modelName: nil,
                    execution: .skip,
                    skipReason: "Manual only mode"
                )
            }
            let s = settings()
            let model = pickGenerativeModel(for: task, settings: s)
            return LocalModelRouteDecision(
                backend: .ollama,
                modelName: model,
                execution: isUserTriggered(task) ? .asyncQueued : .asyncQueued,
                skipReason: nil
            )
        }
    }

    private func pickGenerativeModel(for task: LocalModelTask, settings: ModelSettings) -> String {
        if task == .summary,
           settings.allowUtilityModel,
           let utility = settings.utilityModelName,
           !utility.isEmpty {
            return utility
        }
        return settings.primaryModelName
    }

    private func isUserTriggered(_ task: LocalModelTask) -> Bool {
        switch task {
        case .rewriteProposal, .sceneExpansion, .chapterSplit: true
        default: false
        }
    }
}
