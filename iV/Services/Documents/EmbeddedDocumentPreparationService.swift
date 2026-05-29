import Foundation

enum EmbeddedDocumentPreparationError: LocalizedError, Sendable {
    case missingProjectFolder
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectFolder:
            "Project folder is not available."
        case .persistenceFailed(let detail):
            "Could not prepare the manuscript DOCX file: \(detail)"
        }
    }
}

/// Ensures `manuscript/{id}.docx` exists via `DocumentStore` without overwriting existing files.
@MainActor
struct EmbeddedDocumentPreparationService {
    let documentStore: DocumentStore

    func prepareDocxIfNeeded(document: Document, folder: URL) throws -> (document: Document, docxURL: URL) {
        var doc = document
        do {
            try documentStore.ensurePrimaryDocxFile(document: &doc, folder: folder)
            try documentStore.save(doc, folder: folder)
        } catch {
            throw EmbeddedDocumentPreparationError.persistenceFailed(error.localizedDescription)
        }
        let docxURL: URL
        if let name = doc.docxFileName {
            docxURL = ProjectPaths.manuscriptFolder(in: folder).appendingPathComponent(name)
        } else {
            docxURL = ProjectPaths.documentDocxURL(folder: folder, documentID: doc.id)
        }
        guard FileManager.default.fileExists(atPath: docxURL.path) else {
            throw EmbeddedDocumentPreparationError.persistenceFailed("DOCX file was not created at \(docxURL.path).")
        }
        return (doc, docxURL)
    }
}
