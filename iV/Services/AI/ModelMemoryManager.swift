import Foundation

/// Tracks loaded Ollama models and keep-alive policy. Unload is real when Ollama API supports it.
@MainActor
@Observable
final class ModelMemoryManager {
    var loadedModelName: String?
    var lastUsedAt: Date?
    var stateLabel: String = "No model loaded"

    var maxLoaded: () -> Int = { 1 }

    func markLoaded(_ name: String) {
        loadedModelName = name
        lastUsedAt = Date()
        stateLabel = "Loaded: \(name)"
    }

    func markUnloading() {
        stateLabel = "Unloading model…"
    }

    func markUnloaded() {
        loadedModelName = nil
        stateLabel = "No model loaded"
    }

    /// Before loading `name`, decide if previous model must be unloaded first.
    func shouldUnloadBeforeLoading(_ name: String) -> Bool {
        guard let loaded = loadedModelName, loaded != name else { return false }
        return maxLoaded() <= 1
    }
}
