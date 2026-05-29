import Foundation
import UniformTypeIdentifiers

struct DOCXImportService: DocumentImportService {
    let formatName = "DOCX"
    let capability: ImportExportCapability = .limitedDOCX
    let isAvailable = true

    func importDocument(from url: URL) throws -> ImportedDocument {
        let rich = try DOCXParser.extractRichContent(from: url)
        return ImportedDocument(
            title: url.deletingPathExtension().lastPathComponent,
            plainText: rich.plainText,
            originalSnapshot: rich.plainText,
            formattingSpans: rich.spans.isEmpty ? nil : rich.spans
        )
    }
}

struct DOCXExportService: DocumentExportService {
    let formatName = "DOCX"
    let capability: ImportExportCapability = .limitedDOCX
    let isAvailable = true

    func exportDocument(_ document: Document, to url: URL) throws {
        let paragraphs = TextUtilities.splitParagraphs(document.plainText)
        let chunks = paragraphs.isEmpty ? [document.plainText] : paragraphs
        try DOCXParser.buildDOCXArchive(paragraphs: chunks, spans: document.formattingSpans ?? [], at: url)
    }
}
