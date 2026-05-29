import Foundation

struct ParagraphIndexer {
    func rebuildIndex(
        documentID: UUID,
        text: String,
        existing: DocumentIndex?
    ) -> (DocumentIndex, [ParagraphDirtyState], Set<UUID>) {
        let previous = existing?.paragraphs.map(\.paragraph) ?? []
        let ranged = TextUtilities.splitParagraphsWithRanges(text)
        let chunks = ranged.enumerated().map { order, item in
            ParagraphChunk(text: item.text, rangeStart: item.start, rangeEnd: item.end, order: order)
        }

        let (indexed, dirtyStates, deletedIDs) = ParagraphIdentityMatcher.match(
            chunks: chunks,
            previous: previous,
            documentID: documentID
        )

        let index = DocumentIndex(documentID: documentID, paragraphs: indexed, updatedAt: Date())
        return (index, dirtyStates, deletedIDs)
    }

    func paragraph(at location: Int, index: DocumentIndex) -> Paragraph? {
        index.paragraphs.first { location >= $0.rangeStart && location < $0.rangeEnd }?.paragraph
    }
}

enum ParagraphIndexService {
    static func markDiagnosticsStale(
        diagnostics: inout [Diagnostic],
        dirtyParagraphIDs: Set<UUID>,
        deletedParagraphIDs: Set<UUID>,
        paragraphHashes: [UUID: String]
    ) {
        for i in diagnostics.indices {
            guard let pid = diagnostics[i].paragraphID else { continue }
            if deletedParagraphIDs.contains(pid) {
                diagnostics[i].isStale = true
                diagnostics[i].status = .stale
                diagnostics[i].staleReason = "Paragraph deleted"
            } else if dirtyParagraphIDs.contains(pid) {
                diagnostics[i].isStale = true
                diagnostics[i].status = .stale
                diagnostics[i].staleReason = "Paragraph text changed"
            } else if let hash = paragraphHashes[pid], hash != diagnostics[i].textHashAtCreation {
                diagnostics[i].isStale = true
                diagnostics[i].status = .stale
                diagnostics[i].staleReason = "Paragraph hash mismatch"
            }
        }
    }
}
