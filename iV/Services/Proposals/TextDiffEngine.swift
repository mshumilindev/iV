import Foundation

enum TextDiffEngine {
    static func diff(before: String, after: String) -> [TextDiffChunk] {
        if before == after { return [TextDiffChunk(kind: .unchanged, text: before)] }
        let beforeWords = before.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let afterWords = after.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var chunks: [TextDiffChunk] = []
        var i = 0
        var j = 0
        while i < beforeWords.count || j < afterWords.count {
            if i < beforeWords.count, j < afterWords.count, beforeWords[i] == afterWords[j] {
                chunks.append(.init(kind: .unchanged, text: beforeWords[i] + " "))
                i += 1; j += 1
            } else if j < afterWords.count && (i >= beforeWords.count || !beforeWords[i...].contains(afterWords[j])) {
                chunks.append(.init(kind: .inserted, text: afterWords[j] + " "))
                j += 1
            } else if i < beforeWords.count {
                chunks.append(.init(kind: .deleted, text: beforeWords[i] + " "))
                i += 1
            } else { break }
        }
        return chunks
    }
}

enum ChangeProposalService {
    static func makeProposal(
        projectID: UUID,
        documentID: UUID,
        scope: RuleScope,
        scopeID: UUID?,
        source: ChangeProposalSource,
        title: String,
        reason: String,
        beforeText: String,
        afterText: String,
        riskLevel: RiskLevel
    ) -> ChangeProposal {
        ChangeProposal(
            id: UUID(),
            projectID: projectID,
            documentID: documentID,
            scope: scope,
            scopeID: scopeID,
            source: source,
            title: title,
            reason: reason,
            beforeText: beforeText,
            afterText: afterText,
            diff: TextDiffEngine.diff(before: beforeText, after: afterText),
            riskLevel: riskLevel,
            status: .pending,
            createdAt: Date()
        )
    }
}
