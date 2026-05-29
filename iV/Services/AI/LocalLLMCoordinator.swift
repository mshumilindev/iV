import Foundation

enum LocalLLMError: LocalizedError {
    case skipped(String)
    case noModel
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .skipped(let r): r
        case .noModel: "No model selected for this task."
        case .unavailable(let r): r
        }
    }
}

/// Routes tasks, manages loaded models, and runs Ollama with retry + keep-alive policy.
@MainActor
final class LocalLLMCoordinator {
    let provider: OllamaAIProvider
    let memoryManager = ModelMemoryManager()
    private var router: DefaultLocalModelRouter

    var currentTaskLabel: String?
    var statusDetail: String = "AI idle"

    init() {
        provider = OllamaAIProvider()
        router = DefaultLocalModelRouter(
            settings: { .default },
            performanceMode: { .balanced },
            ollamaEnabled: { false }
        )
        memoryManager.maxLoaded = { 1 }
    }

    func configure(project: Project?, performanceMode: PerformanceMode, health: OllamaHealth) {
        let settings = project?.ollamaSettings ?? .default
        let llmOn = settings.llmPassesEnabled && {
            if case .available = health { return true }
            return false
        }()
        router = DefaultLocalModelRouter(
            settings: { project?.ollamaSettings.resolvedModelSettings ?? .default },
            performanceMode: { performanceMode },
            ollamaEnabled: { llmOn }
        )
        memoryManager.maxLoaded = { settings.resolvedModelSettings.maxLoadedLLMModels }
        updateStatusIdle()
    }

    func route(_ task: LocalModelTask) -> LocalModelRouteDecision {
        router.route(task)
    }

    func runJSONTask<T: Decodable>(
        task: LocalModelTask,
        prompt: String,
        settings: OllamaSettings,
        performanceMode: PerformanceMode,
        as type: T.Type
    ) async throws -> T {
        let decision = router.route(task)
        switch decision.execution {
        case .skip, .mechanicalOnly:
            throw LocalLLMError.skipped(decision.skipReason ?? "Task skipped by router")
        case .synchronous, .asyncQueued:
            break
        }
        guard decision.backend == .ollama else {
            throw LocalLLMError.unavailable("\(decision.backend.rawValue) not available")
        }
        let model = try await prepareModel(name: decision.modelName, settings: settings, policy: settings.resolvedModelSettings.keepAlivePolicy, performanceMode: performanceMode)
        currentTaskLabel = taskLabel(task)
        statusDetail = "Running: \(currentTaskLabel ?? "analysis")"
        defer {
            currentTaskLabel = nil
            updateStatusIdle()
        }
        return try await provider.runJSONTask(prompt: prompt, model: model, settings: settings, as: type)
    }

    func runTextTask(
        task: LocalModelTask,
        prompt: String,
        settings: OllamaSettings,
        performanceMode: PerformanceMode
    ) async throws -> String {
        let decision = router.route(task)
        guard decision.execution != .skip, decision.execution != .mechanicalOnly else {
            throw LocalLLMError.skipped(decision.skipReason ?? "skipped")
        }
        let model = try await prepareModel(name: decision.modelName, settings: settings, policy: settings.resolvedModelSettings.keepAlivePolicy, performanceMode: performanceMode)
        currentTaskLabel = taskLabel(task)
        statusDetail = "Running: \(currentTaskLabel ?? "generation")"
        defer {
            currentTaskLabel = nil
            updateStatusIdle()
        }
        return try await provider.runTextTask(prompt: prompt, model: model, settings: settings)
    }

    func embed(text: String, settings: OllamaSettings, health: OllamaHealth) async throws -> [Float] {
        let decision = router.route(.embeddingUpdate)
        guard decision.execution != .skip else { throw LocalLLMError.skipped(decision.skipReason ?? "embeddings off") }
        guard case .available = health else { throw LocalLLMError.unavailable("Ollama unavailable") }
        let model = settings.embeddingModelName.isEmpty ? "nomic-embed-text" : settings.embeddingModelName
        return try await provider.embed(text: text, model: model, settings: settings)
    }

    func scheduleUnloadIfNeeded(settings: OllamaSettings, policy: KeepAlivePolicy, performanceMode: PerformanceMode) async {
        guard let loaded = memoryManager.loadedModelName else { return }
        let shouldUnload: Bool = switch performanceMode {
        case .quiet, .manualOnly: true
        case .balanced: policy == .quiet
        case .intensive: false
        }
        guard shouldUnload else { return }
        memoryManager.markUnloading()
        statusDetail = "Unloading model…"
        try? await provider.unloadModel(name: loaded, settings: settings)
        memoryManager.markUnloaded()
        updateStatusIdle()
    }

    private func prepareModel(
        name: String?,
        settings: OllamaSettings,
        policy: KeepAlivePolicy,
        performanceMode: PerformanceMode
    ) async throws -> String {
        var model = name ?? ""
        if model.isEmpty {
            model = settings.effectivePrimaryModel
        }
        if model.isEmpty, case .available(let models) = await provider.checkAvailability(settings: settings) {
            model = models.first ?? ""
        }
        guard !model.isEmpty else { throw LocalLLMError.noModel }

        if memoryManager.shouldUnloadBeforeLoading(model) {
            memoryManager.markUnloading()
            statusDetail = "Switching local model…"
            if let previous = memoryManager.loadedModelName {
                try? await provider.unloadModel(name: previous, settings: settings)
            }
            memoryManager.markUnloaded()
        }
        memoryManager.markLoaded(model)
        statusDetail = "Model loaded: \(model)"
        return model
    }

    private func updateStatusIdle() {
        if let loaded = memoryManager.loadedModelName {
            statusDetail = "Model loaded: \(loaded)"
        } else {
            statusDetail = "AI idle"
        }
    }

    private func taskLabel(_ task: LocalModelTask) -> String {
        switch task {
        case .paragraphLLM: "Paragraph analysis"
        case .sceneLogic: "Scene logic"
        case .dialogue: "Dialogue"
        case .atmosphere: "Atmosphere"
        case .rewriteProposal: "Rewrite"
        case .sceneExpansion: "Scene expansion"
        case .chapterSplit: "Chapter split"
        case .summary: "Summary"
        case .canonExtraction: "Canon extraction"
        default: task.rawValue
        }
    }

    static func task(forPipelinePassID id: String) -> LocalModelTask {
        switch id {
        case "dialogue": .dialogue
        case "character-voice": .dialogue
        case "atmosphere": .atmosphere
        case "action": .atmosphere
        case "world": .sceneLogic
        case "causality", "continuity": .sceneLogic
        case "ai-marker": .paragraphLLM
        default: .paragraphLLM
        }
    }
}
