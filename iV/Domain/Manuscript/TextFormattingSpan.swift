import Foundation

/// Character-range formatting preserved across DOCX import/export.
struct TextFormattingSpan: Codable, Hashable, Sendable {
    var start: Int
    var length: Int
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool
    /// 1–6 when paragraph uses a heading style; nil for body text.
    var headingLevel: Int?

    var end: Int { start + length }
}

struct RichImportedContent: Sendable {
    var plainText: String
    var spans: [TextFormattingSpan]
}
