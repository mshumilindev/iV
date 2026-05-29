import Foundation

@MainActor
final class DocumentStore {
    func createManuscript(projectID: UUID, folder: URL, title: String = "Manuscript") throws -> Document {
        let document = Document(
            id: UUID(),
            projectID: projectID,
            title: title,
            type: .manuscript,
            plainText: "",
            originalSnapshot: nil,
            acceptedPlainText: nil,
            formattingSpans: nil,
            storageKind: .plainTextSidecar,
            docxFileName: nil,
            createdAt: Date(),
            updatedAt: Date(),
            version: 1
        )
        try save(document, folder: folder)
        var withDocx = document
        try ensurePrimaryDocxFile(document: &withDocx, folder: folder)
        try save(withDocx, folder: folder)
        return withDocx
    }

    /// Creates `manuscript/{id}.docx` for the embedded office editor (Phase 2).
    func ensurePrimaryDocxFile(document: inout Document, folder: URL) throws {
        let docxURL = ProjectPaths.documentDocxURL(folder: folder, documentID: document.id)
        if !FileManager.default.fileExists(atPath: docxURL.path) {
            let paragraphs = TextUtilities.splitParagraphs(document.plainText)
            let chunks = paragraphs.isEmpty ? [""] : paragraphs
            try DOCXParser.buildDOCXArchive(
                paragraphs: chunks,
                spans: document.formattingSpans ?? [],
                at: docxURL
            )
        }
        document.storageKind = .docxPrimary
        document.docxFileName = docxURL.lastPathComponent
    }

    func save(_ document: Document, folder: URL) throws {
        var updated = document
        updated.updatedAt = Date()
        try AtomicFileWriter.write(updated, to: ProjectPaths.documentURL(folder: folder, documentID: document.id))
    }

    func load(documentID: UUID, folder: URL) throws -> Document {
        try AtomicFileWriter.read(Document.self, from: ProjectPaths.documentURL(folder: folder, documentID: documentID))
    }

    func listDocuments(folder: URL) -> [Document] {
        let manuscriptDir = ProjectPaths.manuscriptFolder(in: folder)
        guard let files = try? FileManager.default.contentsOfDirectory(at: manuscriptDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url -> Document? in
            guard url.pathExtension == "json" else { return nil }
            return try? AtomicFileWriter.read(Document.self, from: url)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveStructure(_ structure: DocumentStructure, documentID: UUID, folder: URL) throws {
        try AtomicFileWriter.write(structure, to: ProjectPaths.structureURL(folder: folder, documentID: documentID))
    }

    func loadStructure(documentID: UUID, folder: URL) throws -> DocumentStructure {
        let url = ProjectPaths.structureURL(folder: folder, documentID: documentID)
        if FileManager.default.fileExists(atPath: url.path) {
            return try AtomicFileWriter.read(DocumentStructure.self, from: url)
        }
        return DocumentStructure(chapters: [], scenes: [])
    }

    func saveIndex(_ index: DocumentIndex, folder: URL) throws {
        try AtomicFileWriter.write(index, to: ProjectPaths.documentIndexURL(folder: folder, documentID: index.documentID))
    }

    func loadIndex(documentID: UUID, folder: URL) throws -> DocumentIndex? {
        let url = ProjectPaths.documentIndexURL(folder: folder, documentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try AtomicFileWriter.read(DocumentIndex.self, from: url)
    }

    func deleteDocument(documentID: UUID, folder: URL) throws {
        let fm = FileManager.default
        let paths = [
            ProjectPaths.documentURL(folder: folder, documentID: documentID),
            ProjectPaths.documentIndexURL(folder: folder, documentID: documentID),
            ProjectPaths.structureURL(folder: folder, documentID: documentID),
            ProjectPaths.diagnosticsURL(folder: folder, documentID: documentID),
            ProjectPaths.proposalsURL(folder: folder, documentID: documentID),
            ProjectPaths.embeddingsURL(folder: folder, documentID: documentID),
            ProjectPaths.acceptedManuscriptURL(folder: folder, documentID: documentID)
        ]
        for path in paths where fm.fileExists(atPath: path.path) {
            try fm.removeItem(at: path)
        }
    }
}
