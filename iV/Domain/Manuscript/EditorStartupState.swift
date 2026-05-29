import Foundation

/// User-facing startup progress for the embedded manuscript editor.
enum EditorStartupState: Sendable, Equatable {
    case idle
    case loading(message: String)
    case ready
    case unavailable(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var loadingMessage: String? {
        if case .loading(let message) = self { return message }
        return nil
    }
}

enum EditorStartupMessage {
    static let preparing = "Preparing manuscript editor…"
    static let preparingManuscriptBridge = "Preparing manuscript files…"
    static let starting = "Starting editor…"
    static let connecting = "Connecting editor…"
    static let almostReady = "Almost ready…"
    static let ready = "Editor ready"
    static let unavailable = "Editor unavailable — you can still browse projects"
}
