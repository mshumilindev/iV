import Foundation

/// Which surface is editing the manuscript.
enum DocumentEditorKind: String, Sendable, CaseIterable {
    /// ONLYOFFICE / Collabora via local Document Server + WKWebView.
    case embeddedOffice
    /// Legacy `NSTextView` — prototype only; not product-final.
    case legacyPrototype
}

enum DocumentEditorConnectionState: Sendable, Equatable {
    case unavailable(String)
    case connecting
    case ready
    case error(String)
}

/// Snapshot of editor selection for AI bridge and status UI.
struct DocumentEditorSelectionSnapshot: Sendable, Equatable {
    var selectedText: String
    var selectionPreview: String
    var location: Int
    var length: Int
    var editorRange: UnknownEditorRange?

    static let empty = DocumentEditorSelectionSnapshot(
        selectedText: "",
        selectionPreview: "",
        location: 0,
        length: 0,
        editorRange: nil
    )

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum DocumentEditorMutationResult: Sendable {
    case applied
    case unavailable(String)
    case failed(String)
}

/// Primary on-disk format for a manuscript document.
enum DocumentStorageKind: String, Codable, Sendable {
    /// JSON sidecar with `plainText` (legacy / analysis mirror).
    case plainTextSidecar
    /// Authoritative `manuscript/{id}.docx` edited by office engine.
    case docxPrimary
}
