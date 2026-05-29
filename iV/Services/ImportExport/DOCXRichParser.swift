import Foundation

enum DOCXRichParser {
    struct ParsedParagraph: Sendable {
        var runs: [ParsedRun]
        var headingLevel: Int?
    }

    struct ParsedRun: Sendable {
        var text: String
        var isBold: Bool
        var isItalic: Bool
        var isUnderline: Bool
    }

    /// Parses WordprocessingML into plain text (paragraph breaks preserved) and formatting spans.
    static func parseRichContent(fromWordDocumentXML xml: String) -> RichImportedContent {
        let paragraphs = parseParagraphs(xml)
        var plain = ""
        var spans: [TextFormattingSpan] = []
        var offset = 0

        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                plain += "\n\n"
                offset += 2
            }
            if let level = paragraph.headingLevel, paragraph.runs.isEmpty || paragraph.runs.allSatisfy({ $0.text.isEmpty }) {
                continue
            }
            let paraStart = offset
            for run in paragraph.runs where !run.text.isEmpty {
                let start = offset
                plain += run.text
                offset += run.text.count
                if run.isBold || run.isItalic || run.isUnderline || paragraph.headingLevel != nil {
                    spans.append(TextFormattingSpan(
                        start: start,
                        length: run.text.count,
                        isBold: run.isBold,
                        isItalic: run.isItalic,
                        isUnderline: run.isUnderline,
                        headingLevel: paragraph.headingLevel
                    ))
                }
            }
            if let level = paragraph.headingLevel, paraStart < offset {
                spans.append(TextFormattingSpan(
                    start: paraStart,
                    length: offset - paraStart,
                    isBold: true,
                    isItalic: false,
                    isUnderline: false,
                    headingLevel: level
                ))
            }
        }

        if plain.isEmpty {
            let fallback = DOCXParser.plainText(fromWordDocumentXML: xml)
            return RichImportedContent(plainText: fallback, spans: [])
        }
        return RichImportedContent(plainText: plain, spans: mergeSpans(spans))
    }

    static func parseParagraphs(_ xml: String) -> [ParsedParagraph] {
        var result: [ParsedParagraph] = []
        let parts = xml.components(separatedBy: "</w:p>")
        for part in parts {
            guard part.contains("<w:p") else { continue }
            let heading = headingLevel(in: part)
            let runs = parseRuns(in: part)
            let text = runs.map(\.text).joined()
            if text.isEmpty && heading == nil { continue }
            result.append(ParsedParagraph(runs: runs.isEmpty ? [ParsedRun(text: "", isBold: false, isItalic: false, isUnderline: false)] : runs, headingLevel: heading))
        }
        return result
    }

    private static func headingLevel(in paragraphXML: String) -> Int? {
        let pattern = #"<w:pStyle[^>]*w:val="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: paragraphXML, range: NSRange(paragraphXML.startIndex..., in: paragraphXML)),
              let range = Range(match.range(at: 1), in: paragraphXML) else { return nil }
        let style = String(paragraphXML[range]).lowercased()
        if style.contains("heading1") || style == "title" { return 1 }
        if style.contains("heading2") { return 2 }
        if style.contains("heading3") { return 3 }
        if style.contains("heading4") { return 4 }
        if style.contains("heading5") { return 5 }
        if style.contains("heading6") { return 6 }
        return nil
    }

    private static func parseRuns(in paragraphXML: String) -> [ParsedRun] {
        let pattern = "(<w:r[^>]*>)(.*?)(</w:r>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let nsRange = NSRange(paragraphXML.startIndex..., in: paragraphXML)
        var runs: [ParsedRun] = []
        regex.enumerateMatches(in: paragraphXML, range: nsRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 4,
                  let openRange = Range(match.range(at: 1), in: paragraphXML),
                  let bodyRange = Range(match.range(at: 2), in: paragraphXML) else { return }
            let openTag = String(paragraphXML[openRange])
            let body = String(paragraphXML[bodyRange])
            let props = openTag + body
            let bold = props.contains("<w:b") && !props.contains("w:val=\"0\"")
            let italic = props.contains("<w:i") && !props.contains("w:val=\"0\"")
            let underline = props.contains("<w:u ") || props.contains("<w:u/>")
            let text = extractText(fromRunBody: body)
            if !text.isEmpty {
                runs.append(ParsedRun(text: text, isBold: bold, isItalic: italic, isUnderline: underline))
            }
        }
        if runs.isEmpty {
            let text = extractText(fromRunBody: paragraphXML)
            if !text.isEmpty {
                runs.append(ParsedRun(text: text, isBold: false, isItalic: false, isUnderline: false))
            }
        }
        return runs
    }

    private static func extractText(fromRunBody xml: String) -> String {
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

    private static func mergeSpans(_ spans: [TextFormattingSpan]) -> [TextFormattingSpan] {
        spans.sorted { $0.start < $1.start }
    }

    /// Builds OOXML body with bold/italic/underline and heading paragraph styles.
    static func buildDocumentXML(paragraphs: [String], spans: [TextFormattingSpan]) -> String {
        let body = paragraphs.enumerated().map { index, paragraphText in
            let paraStart = paragraphs.prefix(index).reduce(0) { $0 + $1.count + 2 }
            let paraEnd = paraStart + paragraphText.count
            let paraSpans = spans.filter { $0.start >= paraStart && $0.end <= paraEnd }
            let level = paraSpans.compactMap(\.headingLevel).min()
            let pStyle: String
            if let level {
                pStyle = "<w:pPr><w:pStyle w:val=\"Heading\(level)\"/></w:pPr>"
            } else {
                pStyle = ""
            }
            if paraSpans.isEmpty {
                let escaped = DOCXParser.escapeXML(paragraphText)
                return "<w:p>\(pStyle)<w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
            }
            var runsXML = ""
            var cursor = 0
            let sorted = paraSpans.sorted { $0.start < $1.start }
            for span in sorted {
                let localStart = span.start - paraStart
                let localEnd = span.end - paraStart
                if localStart > cursor {
                    let chunk = String(paragraphText.dropFirst(cursor).prefix(localStart - cursor))
                    runsXML += plainRunXML(chunk)
                    cursor = localStart
                }
                let chunk = String(paragraphText.dropFirst(localStart).prefix(span.length))
                runsXML += styledRunXML(chunk, span: span)
                cursor = localEnd
            }
            if cursor < paragraphText.count {
                runsXML += plainRunXML(String(paragraphText.dropFirst(cursor)))
            }
            return "<w:p>\(pStyle)\(runsXML)</w:p>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(body)<w:sectPr/></w:body>
        </w:document>
        """
    }

    private static func plainRunXML(_ text: String) -> String {
        let escaped = DOCXParser.escapeXML(text)
        return "<w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
    }

    private static func styledRunXML(_ text: String, span: TextFormattingSpan) -> String {
        let escaped = DOCXParser.escapeXML(text)
        var rPr = ""
        if span.isBold || span.headingLevel != nil { rPr += "<w:b/>" }
        if span.isItalic { rPr += "<w:i/>" }
        if span.isUnderline { rPr += "<w:u w:val=\"single\"/>" }
        let props = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
        return "<w:r>\(props)<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
    }
}
