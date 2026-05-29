import Foundation

/// Result of preparing an embedded ONLYOFFICE editing session for a local manuscript.
enum EmbeddedDocumentSessionOutcome: Sendable, Equatable {
    case unavailable(reason: String, technicalDetail: String?)
    case pending(reason: String, technicalDetail: String?)
    case ready(EmbeddedDocumentSessionReady)
}

/// A real DocsAPI session — local DOCX is served over localhost for Document Server to fetch.
struct EmbeddedDocumentSessionReady: Sendable, Equatable {
    let onlyOfficeServerURL: String
    let documentTitle: String
    let docxFileURL: URL
    let editorHTML: String
    let documentKey: String
    /// URL ONLYOFFICE Document Server uses to download the manuscript (typically host.docker.internal).
    let documentFetchURL: String
    /// Localhost URL for diagnostics in the Mac app.
    let localServingDetail: String
    /// Save-back via ONLYOFFICE callback is handled by LocalManuscriptDocumentServer.
    let saveAvailable: Bool
}

struct LocalDocumentServingRegistration: Sendable, Equatable {
    let path: String
    let documentServerFetchURL: String
    let localDiagnosticsURL: String
}

enum LocalDocumentServingError: LocalizedError, Sendable, Equatable {
    case serverStartFailed(String)
    case fileNotFound
    case documentNotRegistered

    var errorDescription: String? {
        switch self {
        case .serverStartFailed(let detail):
            "Local manuscript HTTP server could not start: \(detail)"
        case .fileNotFound:
            "Manuscript DOCX file does not exist on disk."
        case .documentNotRegistered:
            "Manuscript is not registered with the local document server."
        }
    }
}

/// Serves manuscript DOCX files to ONLYOFFICE Document Server over localhost HTTP.
protocol LocalDocumentServing: Sendable {
    var isRunning: Bool { get }
    func ensureRunning() throws
    func register(documentID: UUID, fileURL: URL) throws -> LocalDocumentServingRegistration
    func unregister(documentID: UUID)
}
