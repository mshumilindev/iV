import Foundation

enum DOCXParser {
    enum ParseError: LocalizedError {
        case unzipFailed
        case documentXMLMissing
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .unzipFailed: "Could not read DOCX archive."
            case .documentXMLMissing: "word/document.xml not found in DOCX."
            case .emptyDocument: "DOCX contains no extractable text."
            }
        }
    }

    /// Extracts plain text and formatting spans from a .docx file.
    static func extractRichContent(from docxURL: URL) throws -> RichImportedContent {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iv-docx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try unzip(docxURL: docxURL, to: tempDir)

        let documentXML = tempDir.appendingPathComponent("word/document.xml")
        guard FileManager.default.fileExists(atPath: documentXML.path) else {
            throw ParseError.documentXMLMissing
        }

        let xml = try String(contentsOf: documentXML, encoding: .utf8)
        let rich = DOCXRichParser.parseRichContent(fromWordDocumentXML: xml)
        guard !rich.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.emptyDocument
        }
        return rich
    }

    /// Extracts plain text from a .docx file (paragraph breaks preserved).
    static func extractPlainText(from docxURL: URL) throws -> String {
        try extractRichContent(from: docxURL).plainText
    }

    private static func unzip(docxURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", docxURL.path, "-d", destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ParseError.unzipFailed
        }
    }

    /// Parses WordprocessingML body text from document.xml.
    static func plainText(fromWordDocumentXML xml: String) -> String {
        var paragraphs: [String] = []
        var currentParagraph = ""
        var insideText = false
        var buffer = ""

        let scanner = xml.unicodeScalars
        var i = xml.startIndex
        while i < xml.endIndex {
            if xml[i...].hasPrefix("</w:p>") {
                if !currentParagraph.isEmpty || !buffer.isEmpty {
                    currentParagraph += buffer
                    buffer = ""
                }
                let trimmed = currentParagraph.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { paragraphs.append(trimmed) }
                currentParagraph = ""
                insideText = false
                i = xml.index(i, offsetBy: 6)
                continue
            }
            if xml[i...].hasPrefix("<w:t") {
                if let close = xml[i...].firstIndex(of: ">") {
                    i = xml.index(after: close)
                    insideText = true
                    buffer = ""
                    continue
                }
            }
            if insideText, xml[i...].hasPrefix("</w:t>") {
                currentParagraph += decodeXMLEntities(buffer)
                buffer = ""
                insideText = false
                i = xml.index(i, offsetBy: 6)
                continue
            }
            if insideText {
                buffer.append(xml[i])
            }
            i = xml.index(after: i)
        }

        if !currentParagraph.isEmpty || !buffer.isEmpty {
            currentParagraph += decodeXMLEntities(buffer)
            if !currentParagraph.isEmpty { paragraphs.append(currentParagraph) }
        }

        if paragraphs.isEmpty {
            return fallbackRegexExtract(xml)
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func fallbackRegexExtract(_ xml: String) -> String {
        let pattern = "<w:t[^>]*>([^<]*)</w:t>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        let parts = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            return decodeXMLEntities(String(xml[range]))
        }
        return parts.joined()
    }

    private static func decodeXMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Builds a valid DOCX with optional character-level formatting.
    static func buildDOCXArchive(paragraphs: [String], spans: [TextFormattingSpan] = [], at outputURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iv-docx-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)
        let wordRelsDir = wordDir.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

        let documentXML = DOCXRichParser.buildDocumentXML(paragraphs: paragraphs, spans: spans)

        try documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)
        try contentTypesXML.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try wordRelsXML.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.currentDirectoryURL = tempDir
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", outputURL.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ParseError.unzipFailed
        }
    }

    static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static let wordRelsXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
    """
}
