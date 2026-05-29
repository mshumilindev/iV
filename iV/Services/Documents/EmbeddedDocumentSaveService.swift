import Foundation

struct EmbeddedDocumentSaveResult: Sendable {
    let documentID: UUID
    let docxURL: URL
    let plainText: String
    let formattingSpans: [TextFormattingSpan]
}

enum EmbeddedDocumentSaveServiceError: LocalizedError {
    case plainTextExtractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .plainTextExtractionFailed(let detail):
            "Saved DOCX could not be indexed: \(detail)"
        }
    }
}

/// Applies ONLYOFFICE save-back to in-app document metadata without touching import snapshots.
enum EmbeddedDocumentSaveService {
    static func syncDocumentMetadata(
        document: inout Document,
        savedDocxURL: URL
    ) throws -> EmbeddedDocumentSaveResult {
        let rich = try DOCXParser.extractRichContent(from: savedDocxURL)
        document.plainText = rich.plainText
        document.formattingSpans = rich.spans
        document.storageKind = .docxPrimary
        document.docxFileName = savedDocxURL.lastPathComponent
        document.updatedAt = Date()
        return EmbeddedDocumentSaveResult(
            documentID: document.id,
            docxURL: savedDocxURL,
            plainText: rich.plainText,
            formattingSpans: rich.spans
        )
    }
}
