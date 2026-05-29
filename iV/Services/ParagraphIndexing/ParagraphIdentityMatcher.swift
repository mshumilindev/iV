import Foundation

struct ParagraphChunk: Sendable, Equatable {
    var text: String
    var rangeStart: Int
    var rangeEnd: Int
    var order: Int
}

enum ParagraphMatchKind: String, Sendable {
    case exactHash
    case sameOrderSameHash
    case sameOrderSimilarity
    case contextSimilarity
    case newParagraph
}

struct ParagraphMatchAssignment: Sendable {
    var newOrder: Int
    var previous: Paragraph?
    var kind: ParagraphMatchKind
    var confidence: Double
}

/// Preserves paragraph IDs across edits using hash, order, similarity, and bounded context.
enum ParagraphIdentityMatcher {
    /// Context / moved-paragraph matching.
    static let similarityThreshold = 0.82
    /// Minimum confidence to reuse a paragraph ID (lower than context match bar).
    static let identityReuseThreshold = 0.55
    /// Same-order slot: preserve ID for in-place edits even when hash changes.
    static let sameOrderAnchorThreshold = 0.38
    static let structureIDThreshold = 0.88
    static let contextSearchRadius = 3

    static func match(
        chunks: [ParagraphChunk],
        previous: [Paragraph],
        documentID: UUID
    ) -> (
        indexed: [IndexedParagraph],
        dirtyStates: [ParagraphDirtyState],
        deletedParagraphIDs: Set<UUID>
    ) {
        var assignments = Array<ParagraphMatchAssignment?>(repeating: nil, count: chunks.count)
        var usedPreviousIDs = Set<UUID>()

        let previousByOrder: [Int: Paragraph] = Dictionary(
            uniqueKeysWithValues: previous.map { ($0.order, $0) }
        )

        func assign(_ index: Int, _ paragraph: Paragraph, kind: ParagraphMatchKind, confidence: Double) {
            guard assignments[index] == nil, !usedPreviousIDs.contains(paragraph.id) else { return }
            assignments[index] = ParagraphMatchAssignment(
                newOrder: index,
                previous: paragraph,
                kind: kind,
                confidence: confidence
            )
            usedPreviousIDs.insert(paragraph.id)
        }

        func unmatchedPrevious() -> [Paragraph] {
            previous.filter { !usedPreviousIDs.contains($0.id) }
        }

        // 1. Exact hash among unmatched (prefer closest order).
        for (index, chunk) in chunks.enumerated() where assignments[index] == nil {
            let hash = String(TextUtilities.hashText(chunk.text))
            let candidates = unmatchedPrevious().filter { $0.hash == hash }
            guard let best = candidates.min(by: { abs($0.order - index) < abs($1.order - index) }) else { continue }
            assign(index, best, kind: .exactHash, confidence: 1)
        }

        // 2. Same order + same hash.
        for (index, chunk) in chunks.enumerated() where assignments[index] == nil {
            guard let old = previousByOrder[index], !usedPreviousIDs.contains(old.id) else { continue }
            let hash = String(TextUtilities.hashText(chunk.text))
            guard old.hash == hash else { continue }
            assign(index, old, kind: .sameOrderSameHash, confidence: 1)
        }

        // 3. Same order + text similarity (in-place edit; lower bar than context matching).
        let sameLength = chunks.count == previous.count
        for (index, chunk) in chunks.enumerated() where assignments[index] == nil {
            guard let old = previousByOrder[index], !usedPreviousIDs.contains(old.id) else { continue }
            let sim = ParagraphTextSimilarity.ratio(chunk.text, old.text)
            if sameLength && sim >= sameOrderAnchorThreshold {
                assign(index, old, kind: .sameOrderSimilarity, confidence: sim)
                continue
            }
            guard sim >= similarityThreshold else { continue }
            assign(index, old, kind: .sameOrderSimilarity, confidence: sim)
        }

        // 4. Nearby order + context similarity.
        for (index, chunk) in chunks.enumerated() where assignments[index] == nil {
            let prevNew = index > 0 ? chunks[index - 1].text : nil
            let nextNew = index + 1 < chunks.count ? chunks[index + 1].text : nil

            var best: (Paragraph, Double)?
            for old in unmatchedPrevious() where abs(old.order - index) <= contextSearchRadius {
                let prevOld = previousByOrder[old.order - 1]?.text
                let nextOld = previousByOrder[old.order + 1]?.text
                let sim = ParagraphTextSimilarity.contextRatio(
                    previousNew: prevNew,
                    currentNew: chunk.text,
                    nextNew: nextNew,
                    previousOld: prevOld,
                    currentOld: old.text,
                    nextOld: nextOld
                )
                if sim >= identityReuseThreshold, sim > (best?.1 ?? -1) {
                    best = (old, sim)
                }
            }
            if let best, best.1 >= identityReuseThreshold {
                assign(index, best.0, kind: .contextSimilarity, confidence: best.1)
            }
        }

        let deletedParagraphIDs = Set(previous.map(\.id).filter { !usedPreviousIDs.contains($0) })

        var indexed: [IndexedParagraph] = []
        var dirtyStates: [ParagraphDirtyState] = []
        let now = Date()

        for (index, chunk) in chunks.enumerated() {
            let hash = String(TextUtilities.hashText(chunk.text))
            let assignment = assignments[index]
            let preserved = assignment?.previous
            let confidence = assignment?.confidence ?? 0
            let kind = assignment?.kind ?? .newParagraph

            let paragraphID: UUID
            let sceneID: UUID?
            let chapterID: UUID?
            var dirtyReasons: [String] = []

            let sameLength = chunks.count == previous.count
            let anchoredInPlace = kind == .sameOrderSimilarity
                && sameLength
                && confidence >= sameOrderAnchorThreshold

            if assignment == nil {
                paragraphID = UUID()
                sceneID = nil
                chapterID = nil
                dirtyReasons.append("inserted")
            } else if anchoredInPlace {
                paragraphID = preserved!.id
                sceneID = confidence >= structureIDThreshold ? preserved?.sceneID : nil
                chapterID = confidence >= structureIDThreshold ? preserved?.chapterID : nil
            } else if confidence < identityReuseThreshold {
                paragraphID = UUID()
                sceneID = nil
                chapterID = nil
                dirtyReasons.append("lowConfidenceMatch")
            } else {
                paragraphID = preserved!.id
                sceneID = confidence >= structureIDThreshold ? preserved?.sceneID : nil
                chapterID = confidence >= structureIDThreshold ? preserved?.chapterID : nil
            }

            let previousHash = preserved?.hash
            let textChanged = previousHash != hash

            if textChanged || !dirtyReasons.isEmpty {
                if textChanged, !dirtyReasons.contains("inserted") {
                    dirtyReasons.insert("textChanged", at: 0)
                }
                dirtyStates.append(
                    ParagraphDirtyState(
                        paragraphID: paragraphID,
                        previousHash: previousHash,
                        currentHash: hash,
                        changedAt: now,
                        dirtyReasons: dirtyReasons,
                        affectedScopes: DirtyScopePropagation.scopes(
                            forParagraphOrder: index,
                            totalParagraphs: chunks.count,
                            includeProject: true
                        )
                    )
                )
            }

            let paragraph = Paragraph(
                id: paragraphID,
                sceneID: sceneID,
                chapterID: chapterID,
                documentID: documentID,
                order: index,
                text: chunk.text,
                hash: hash,
                wordCount: TextUtilities.wordCount(chunk.text),
                sentenceCount: TextUtilities.sentenceCount(chunk.text),
                lastAnalyzedHash: preserved?.lastAnalyzedHash,
                createdAt: preserved?.createdAt ?? now,
                updatedAt: now
            )

            indexed.append(
                IndexedParagraph(paragraph: paragraph, rangeStart: chunk.rangeStart, rangeEnd: chunk.rangeEnd)
            )
        }

        return (indexed, dirtyStates, deletedParagraphIDs)
    }
}

enum DirtyScopePropagation {
    private static let baseScopes: [RuleScope] = [
        .sentence, .paragraph, .paragraphWindow, .scene, .chapterSection, .chapter, .document
    ]

    static func scopes(forParagraphOrder order: Int, totalParagraphs: Int, includeProject: Bool) -> [RuleScope] {
        var scopes = baseScopes
        if includeProject {
            scopes.append(.project)
        }
        if order > 0 {
            scopes.append(.previousSceneCurrentScene)
            scopes.append(.previousChapterCurrentChapter)
        }
        _ = totalParagraphs
        return scopes
    }
}
