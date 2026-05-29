import AppKit
import Foundation
import UniformTypeIdentifiers

protocol DocumentImportService: Sendable {
    var formatName: String { get }
    var capability: ImportExportCapability { get }
    var isAvailable: Bool { get }
    func importDocument(from url: URL) throws -> ImportedDocument
}

protocol DocumentExportService: Sendable {
    var formatName: String { get }
    var capability: ImportExportCapability { get }
    var isAvailable: Bool { get }
    func exportDocument(_ document: Document, to url: URL) throws
}

struct ImportedDocument: Sendable {
    var title: String
    var plainText: String
    var originalSnapshot: String?
    var formattingSpans: [TextFormattingSpan]?
}

struct PlainTextImportService: DocumentImportService {
    let formatName = "Plain Text"
    let capability: ImportExportCapability = .full
    let isAvailable = true

    func importDocument(from url: URL) throws -> ImportedDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        return ImportedDocument(title: url.deletingPathExtension().lastPathComponent, plainText: text, originalSnapshot: text)
    }
}

struct PlainTextExportService: DocumentExportService {
    let formatName = "Plain Text"
    let capability: ImportExportCapability = .full
    let isAvailable = true

    func exportDocument(_ document: Document, to url: URL) throws {
        try document.plainText.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct RTFImportService: DocumentImportService {
    let formatName = "RTF"
    let capability: ImportExportCapability = .textOnly
    let isAvailable = true

    func importDocument(from url: URL) throws -> ImportedDocument {
        let data = try Data(contentsOf: url)
        let attributed = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let plain = attributed.string
        return ImportedDocument(
            title: url.deletingPathExtension().lastPathComponent,
            plainText: plain,
            originalSnapshot: plain,
            formattingSpans: nil
        )
    }
}

struct RTFExportService: DocumentExportService {
    let formatName = "RTF"
    let capability: ImportExportCapability = .textOnly
    let isAvailable = true

    func exportDocument(_ document: Document, to url: URL) throws {
        // Exports working plain text as a minimal RTF document — no span roundtrip.
        let attributed = NSAttributedString(string: document.plainText)
        let range = NSRange(location: 0, length: attributed.length)
        let data = try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try data.write(to: url)
    }
}

enum ImportExportCoordinator {
    @MainActor
    static func pickAndImport(service: DocumentImportService) throws -> ImportedDocument {
        guard service.isAvailable else {
            throw NSError(
                domain: "iV.Import",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(service.menuLabel) import is not available."]
            )
        }
        guard let url = pickOpenURL(for: service) else {
            throw NSError(domain: "iV.Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "Import cancelled."])
        }
        return try service.importDocument(from: url)
    }

    @MainActor
    static func importFile(
        service: DocumentImportService,
        projectID: UUID,
        folder: URL,
        documentStore: DocumentStore
    ) throws -> Document {
        guard service.isAvailable else {
            throw NSError(
                domain: "iV.Import",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(service.menuLabel) import is not available."]
            )
        }
        let imported = try pickAndImport(service: service)
        var document = try documentStore.createManuscript(projectID: projectID, folder: folder, title: imported.title)
        document.plainText = imported.plainText
        document.originalSnapshot = imported.originalSnapshot
        document.formattingSpans = imported.formattingSpans
        var saved = document
        if let snapshot = imported.originalSnapshot {
            saved.originalSnapshot = snapshot
            let snapURL = ProjectPaths.snapshotsFolder(in: folder)
                .appendingPathComponent("\(document.id.uuidString)-import.txt")
            try AtomicFileWriter.write(text: snapshot, to: snapURL)
        }
        try documentStore.save(saved, folder: folder)
        return saved
    }

    @MainActor
    static func exportFile(service: DocumentExportService, document: Document) throws {
        guard service.isAvailable else {
            throw NSError(
                domain: "iV.Export",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(service.menuLabel) export is not available."]
            )
        }
        guard let url = pickSaveURL(for: service, documentTitle: document.title) else {
            throw NSError(domain: "iV.Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Export cancelled."])
        }
        try service.exportDocument(document, to: url)
    }

    @MainActor
    private static func pickOpenURL(for service: DocumentImportService) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = service.limitationSummary
        if service is PlainTextImportService {
            panel.allowedContentTypes = [.plainText, .text]
        } else if service is RTFImportService {
            panel.allowedContentTypes = [.rtf]
        } else if service is DOCXImportService {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        } else {
            panel.allowedContentTypes = [.data]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private static func pickSaveURL(for service: DocumentExportService, documentTitle: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = documentTitle
        panel.message = service.limitationSummary
        if service is PlainTextExportService {
            panel.allowedContentTypes = [.plainText]
        } else if service is RTFExportService {
            panel.allowedContentTypes = [.rtf]
        } else if service is DOCXExportService {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        } else {
            panel.allowedContentTypes = [.data]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
