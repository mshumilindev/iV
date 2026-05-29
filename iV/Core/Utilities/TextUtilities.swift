import Foundation
import CryptoKit
import NaturalLanguage

enum TextUtilities {
    static func hashText(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }

    static func wordCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func sentenceCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return max(count, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    /// Paragraph text with UTF-16 ranges in normalized `\n` manuscript text (single pass; mirrors `splitParagraphs`).
    static func splitParagraphsWithRanges(_ text: String) -> [(text: String, start: Int, end: Int)] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [(text: String, start: Int, end: Int)] = []
        var current = ""
        var startOffset: Int?

        func flush(endOffset: Int) {
            let trimmed = current.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty, let start = startOffset else { return }
            result.append((trimmed, start, endOffset))
            current = ""
            startOffset = nil
        }

        var lineStart = normalized.startIndex
        while lineStart < normalized.endIndex {
            let lineEnd = normalized[lineStart...].firstIndex(of: "\n") ?? normalized.endIndex
            let line = String(normalized[lineStart..<lineEnd])
            let lineStartOffset = normalized.distance(from: normalized.startIndex, to: lineStart)

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush(endOffset: lineStartOffset)
            } else {
                if startOffset == nil { startOffset = lineStartOffset }
                if !current.isEmpty { current += "\n" }
                current += line
            }

            lineStart = lineEnd == normalized.endIndex ? lineEnd : normalized.index(after: lineEnd)
        }

        flush(endOffset: normalized.count)
        return result
    }

    static func splitParagraphs(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(current.trimmingCharacters(in: .newlines))
                    current = ""
                }
            } else {
                if !current.isEmpty { current += "\n" }
                current += line
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(current.trimmingCharacters(in: .newlines))
        }
        return result
    }

    static func containsLatinInCyrillicContext(_ text: String) -> Bool {
        let latin = CharacterSet(charactersIn: "A"..."Z").union(CharacterSet(charactersIn: "a"..."z"))
        let cyrillic = CharacterSet(charactersIn: "\u{0400}"..."\u{04FF}")
        let hasLatin = text.unicodeScalars.contains { latin.contains($0) }
        let hasCyrillic = text.unicodeScalars.contains { cyrillic.contains($0) }
        return hasLatin && hasCyrillic
    }
}

struct UUIDFactory {
    static func make() -> UUID { UUID() }
}

struct DateProvider {
    static func now() -> Date { Date() }
}
