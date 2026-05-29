import Foundation

/// User-facing lifecycle for the embedded ONLYOFFICE manuscript surface.
enum EmbeddedEditorLifecycle: Sendable, Equatable {
    case idle
    case noDocument
    case checkingServer
    case serverUnavailable(reason: String, technicalDetail: String?)
    case preparingDocument
    case loadingDocument
    case startingDocumentServer(message: String?)
    /// Document Server responded; WOPI/JS editing bridge not connected yet.
    case bridgePending(documentTitle: String, docxPath: String?)
    case ready(documentTitle: String, docxPath: String?)
    case failed(message: String, technicalDetail: String?)

    var isBusy: Bool {
        switch self {
        case .checkingServer, .preparingDocument, .loadingDocument, .startingDocumentServer:
            true
        default:
            false
        }
    }

    var userFacingTitle: String {
        switch self {
        case .idle:
            "Editor"
        case .noDocument:
            "No manuscript"
        case .checkingServer:
            "Checking Document Server"
        case .serverUnavailable:
            "Document Server unavailable"
        case .preparingDocument:
            "Preparing manuscript"
        case .loadingDocument:
            "Opening manuscript"
        case .startingDocumentServer:
            "Starting Document Server"
        case .bridgePending:
            "Document Server reachable"
        case .ready:
            "Editor ready"
        case .failed:
            "Manuscript unavailable"
        }
    }
}

extension DocumentEditorKind {
    var statusLabel: String {
        switch self {
        case .embeddedOffice:
            "Embedded office"
        case .legacyPrototype:
            "Legacy prototype fallback"
        }
    }

    var settingsLabel: String {
        switch self {
        case .embeddedOffice:
            "Embedded office (ONLYOFFICE) — default"
        case .legacyPrototype:
            "Legacy prototype (NSTextView) — development fallback"
        }
    }
}
