import Foundation

/// Keeps diagnostic evidence scoped to a short excerpt, not whole-manuscript dumps.
enum DiagnosticEvidence {
    static let maxLength = 320

    static func clamp(_ evidence: String, paragraphText: String? = nil, maxLength: Int = maxLength) -> String {
        let trimmed = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let paragraphText, trimmed.count > paragraphText.count + 40,
           paragraphText.count <= maxLength {
            return paragraphText
        }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    static func llmPassFailure(
        projectID: UUID,
        documentID: UUID,
        passName: String,
        error: String,
        paragraphID: UUID? = nil
    ) -> Diagnostic {
        Diagnostic(
            id: UUID(),
            projectID: projectID,
            documentID: documentID,
            chapterID: nil,
            sceneID: nil,
            paragraphID: paragraphID,
            ruleID: nil,
            source: .pipeline,
            severity: .error,
            scope: .paragraph,
            title: "LLM pass failed: \(passName)",
            message: clamp(error, maxLength: 240),
            evidence: "Pass: \(passName)",
            startOffset: nil,
            endOffset: nil,
            suggestedFix: nil,
            fixLevel: .humanOnly,
            status: .open,
            textHashAtCreation: nil,
            scopeHashAtCreation: nil,
            isStale: false,
            staleReason: nil,
            createdAt: Date()
        )
    }
}
