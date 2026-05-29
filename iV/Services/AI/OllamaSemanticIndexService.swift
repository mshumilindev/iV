import Foundation

struct ParagraphEmbedding: Codable, Hashable, Sendable {
    var paragraphID: UUID
    var vector: [Float]
}

struct EmbeddingIndex: Codable, Sendable {
    var documentID: UUID
    var model: String
    var paragraphs: [ParagraphEmbedding]
    var updatedAt: Date
}

enum EmbeddingMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return Double(dot / denom)
    }
}

/// Semantic search via Ollama `/api/embeddings`, with lexical fallback.
final class OllamaSemanticIndexService: SemanticIndexServiceProtocol, @unchecked Sendable {
    private let provider: any LocalAIProvider
    private let lexical = LexicalSemanticIndexService()
    private var embeddings: [UUID: [Float]] = [:]
    private var modelUsed = ""
    private(set) var lastMode: String = "lexical"

    var isEnabled: Bool { true }

    init(provider: any LocalAIProvider) {
        self.provider = provider
    }

    func loadPersisted(index: EmbeddingIndex?) {
        guard let index else {
            embeddings = [:]
            return
        }
        modelUsed = index.model
        embeddings = Dictionary(uniqueKeysWithValues: index.paragraphs.map { ($0.paragraphID, $0.vector) })
        lastMode = "ollama (cached)"
    }

    func persistedIndex(documentID: UUID) -> EmbeddingIndex? {
        guard !embeddings.isEmpty else { return nil }
        return EmbeddingIndex(
            documentID: documentID,
            model: modelUsed,
            paragraphs: embeddings.map { ParagraphEmbedding(paragraphID: $0.key, vector: $0.value) },
            updatedAt: Date()
        )
    }

    func index(
        paragraphs: [Paragraph],
        settings: OllamaSettings,
        health: OllamaHealth,
        onlyParagraphIDs: Set<UUID>? = nil
    ) async {
        await lexical.index(paragraphs: paragraphs)
        guard settings.embeddingsEnabled, settings.resolvedModelSettings.allowEmbeddings else {
            lastMode = "lexical"
            return
        }
        guard case .available = health else {
            lastMode = "lexical (Ollama unavailable)"
            return
        }

        let model = settings.embeddingModelName.isEmpty ? "nomic-embed-text" : settings.embeddingModelName
        var updated = embeddings
        let targets = paragraphs.filter { p in
            guard let only = onlyParagraphIDs else { return true }
            return only.contains(p.id)
        }
        var embedded = 0
        for paragraph in targets {
            let snippet = String(paragraph.text.prefix(2000))
            guard !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let vector = try? await provider.embed(text: snippet, model: model, settings: settings), !vector.isEmpty {
                updated[paragraph.id] = vector
                embedded += 1
            }
        }
        embeddings = updated
        if embedded > 0 {
            modelUsed = model
            lastMode = onlyParagraphIDs == nil ? "ollama (\(model))" : "ollama delta (\(embedded))"
        } else if embeddings.isEmpty {
            lastMode = "lexical (embedding failed)"
        }
    }

    func index(paragraphs: [Paragraph]) async {
        await lexical.index(paragraphs: paragraphs)
    }

    func search(query: String, limit: Int) async -> [UUID] {
        await lexical.search(query: query, limit: limit)
    }

    func search(query: String, limit: Int, settings: OllamaSettings) async -> [UUID] {
        if settings.embeddingsEnabled, !embeddings.isEmpty {
            let model = modelUsed.isEmpty ? settings.embeddingModelName : modelUsed
            if let queryVector = try? await provider.embed(text: query, model: model, settings: settings), !queryVector.isEmpty {
                return embeddings
                    .map { (id, vector) in (id, EmbeddingMath.cosineSimilarity(queryVector, vector)) }
                    .filter { $0.1 > 0.2 }
                    .sorted { $0.1 > $1.1 }
                    .prefix(limit)
                    .map(\.0)
            }
        }
        return await lexical.search(query: query, limit: limit)
    }

    func similar(to paragraphID: UUID, limit: Int) async -> [UUID] {
        guard let source = embeddings[paragraphID], !embeddings.isEmpty else {
            return await lexical.similar(to: paragraphID, limit: limit)
        }
        return embeddings
            .filter { $0.key != paragraphID }
            .map { (id, vector) in (id, EmbeddingMath.cosineSimilarity(source, vector)) }
            .filter { $0.1 > 0.35 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

@MainActor
enum EmbeddingIndexStore {
    static func load(documentID: UUID, folder: URL) throws -> EmbeddingIndex? {
        let url = ProjectPaths.embeddingsURL(folder: folder, documentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try AtomicFileWriter.read(EmbeddingIndex.self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    static func save(_ index: EmbeddingIndex, folder: URL) throws {
        try AtomicFileWriter.write(index, to: ProjectPaths.embeddingsURL(folder: folder, documentID: index.documentID))
    }
}
