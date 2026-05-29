import Foundation

/// Distinguishes embedded office integration phases for status UI and debugging.
enum DocumentEditorIntegrationStatus: Sendable, Equatable {
    case embeddedOfficeSelected
    case legacyFallbackSelected
    case documentServerUnavailable
    case bridgeNotImplemented
    case editorSessionReady

    var statusLine: String {
        switch self {
        case .embeddedOfficeSelected:
            "Embedded office selected"
        case .legacyFallbackSelected:
            "Legacy fallback selected (development only)"
        case .documentServerUnavailable:
            "Document Server unavailable"
        case .bridgeNotImplemented:
            "Document Server reachable — editing session pending"
        case .editorSessionReady:
            "ONLYOFFICE editor session active"
        }
    }

    var isWarning: Bool {
        switch self {
        case .legacyFallbackSelected, .documentServerUnavailable, .bridgeNotImplemented:
            true
        case .embeddedOfficeSelected, .editorSessionReady:
            false
        }
    }

    static func resolve(
        editorKind: DocumentEditorKind,
        lifecycle: EmbeddedEditorLifecycle,
        bridgeConnected: Bool,
        editorHostReady: Bool
    ) -> DocumentEditorIntegrationStatus {
        if editorKind == .legacyPrototype {
            return .legacyFallbackSelected
        }
        switch lifecycle {
        case .ready where bridgeConnected && editorHostReady:
            return .editorSessionReady
        case .bridgePending:
            return .bridgeNotImplemented
        case .serverUnavailable, .failed:
            return .documentServerUnavailable
        default:
            return .embeddedOfficeSelected
        }
    }
}
