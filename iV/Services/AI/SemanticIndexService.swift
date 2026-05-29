import Foundation

/// Lexical index today; embedding backends can be plugged in later.
protocol SemanticIndexServiceProtocol: Sendable {
    var isEnabled: Bool { get }
    func index(paragraphs: [Paragraph]) async
    func search(query: String, limit: Int) async -> [UUID]
    func similar(to paragraphID: UUID, limit: Int) async -> [UUID]
}

final class LexicalSemanticIndexService: SemanticIndexServiceProtocol, @unchecked Sendable {
    let isEnabled = true
    private var tokensByParagraph: [UUID: Set<String>] = [:]

    func index(paragraphs: [Paragraph]) async {
        tokensByParagraph = Dictionary(uniqueKeysWithValues: paragraphs.map { p in
            let tokens = Set(
                p.text.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 3 }
            )
            return (p.id, tokens)
        })
    }

    func search(query: String, limit: Int) async -> [UUID] {
        let queryTokens = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
        )
        guard !queryTokens.isEmpty else { return [] }
        return tokensByParagraph
            .map { (id, tokens) in (id, queryTokens.intersection(tokens).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func similar(to paragraphID: UUID, limit: Int) async -> [UUID] {
        guard let source = tokensByParagraph[paragraphID] else { return [] }
        return tokensByParagraph
            .filter { $0.key != paragraphID }
            .map { (id, tokens) in (id, jaccard(source, tokens)) }
            .filter { $0.1 > 0.25 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}

/// Placeholder for future Ollama/Core ML embedding backends.
struct DisabledSemanticIndexService: SemanticIndexServiceProtocol {
    let isEnabled = false
    func index(paragraphs: [Paragraph]) async {}
    func search(query: String, limit: Int) async -> [UUID] { [] }
    func similar(to paragraphID: UUID, limit: Int) async -> [UUID] { [] }
}
