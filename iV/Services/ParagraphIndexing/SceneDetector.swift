import Foundation

struct SceneBreakDetection: Sendable {
    var isBreak: Bool
    var source: SceneBoundarySource
    var confidence: Double
}

/// Deterministic scene boundary signals (MVP — no AI).
enum SceneDetector {
    static func analyzeParagraph(_ text: String) -> SceneBreakDetection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return SceneBreakDetection(isBreak: false, source: .blankGap, confidence: 0)
        }
        if isExplicitSeparator(trimmed) {
            return SceneBreakDetection(isBreak: true, source: .separatorMarker, confidence: 0.95)
        }
        if let title = detectSceneTitle(trimmed) {
            _ = title
            return SceneBreakDetection(isBreak: true, source: .autoDetected, confidence: 0.75)
        }
        return SceneBreakDetection(isBreak: false, source: .autoDetected, confidence: 0)
    }

    /// Finds blank-gap scene candidates in raw text (3+ newlines between content).
    static func blankGapParagraphStarts(in plainText: String, paragraphs: [Paragraph]) -> Set<UUID> {
        guard paragraphs.count > 1 else { return [] }
        var result = Set<UUID>()
        let normalized = plainText.replacingOccurrences(of: "\r\n", with: "\n")
        var searchStart = normalized.startIndex
        for para in paragraphs.dropFirst() {
            guard let range = normalized.range(of: para.text, range: searchStart..<normalized.endIndex) else { continue }
            let gapStart = searchStart
            let gapText = String(normalized[gapStart..<range.lowerBound])
            if gapText.filter({ $0 == "\n" }).count >= 2 {
                result.insert(para.id)
            }
            searchStart = range.upperBound
        }
        return result
    }

    static func isExplicitSeparator(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == "***" || t == "* * *" || t == "---" || t == "———" || t == "###" || t == "#" { return true }
        if t.hasPrefix("***") && t.count <= 24 { return true }
        return false
    }

    static func detectSceneTitle(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenePattern = #"^(?i)(scene|сцена)\s+(\d+)"#
        if let regex = try? NSRegularExpression(pattern: scenePattern),
           let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
            return (t as NSString).substring(with: match.range)
        }
        if t.count <= 40, let regex = try? NSRegularExpression(pattern: #"^\d+\.?$"#),
           regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
            return t
        }
        return nil
    }

    static func scenePreview(from paragraphs: [Paragraph], startID: UUID, endID: UUID?) -> String {
        let slice = paragraphs.filter { p in
            guard let endID else { return p.id == startID }
            guard let startOrder = paragraphs.first(where: { $0.id == startID })?.order,
                  let endOrder = paragraphs.first(where: { $0.id == endID })?.order else {
                return p.id == startID
            }
            return p.order >= startOrder && p.order <= endOrder
        }
        let text = slice.map(\.text).joined(separator: " ")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 72 { return trimmed }
        return String(trimmed.prefix(72)) + "…"
    }

    static func metrics(for paragraphs: [Paragraph], startID: UUID, endID: UUID?) -> (words: Int, characters: Int) {
        let slice = paragraphs.filter { p in
            guard let endID else { return p.id == startID }
            guard let startOrder = paragraphs.first(where: { $0.id == startID })?.order,
                  let endOrder = paragraphs.first(where: { $0.id == endID })?.order else {
                return p.id == startID
            }
            return p.order >= startOrder && p.order <= endOrder
        }
        let text = slice.map(\.text).joined(separator: "\n\n")
        return (TextUtilities.wordCount(text), text.count)
    }
}
