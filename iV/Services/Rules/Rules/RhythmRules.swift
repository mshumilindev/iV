import Foundation

struct ExcessiveShortSentencesRule: ProseRule {
    let id = "rhythm.shortSentences"
    let title = "Excessive short sentences in a row"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let sentences = input.currentText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var streak = 0
        var maxStreak = 0
        for sentence in sentences {
            let words = TextUtilities.wordCount(sentence)
            if words <= 6 { streak += 1; maxStreak = max(maxStreak, streak) } else { streak = 0 }
        }
        guard maxStreak >= 4 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "\(maxStreak) very short sentences appear in sequence.",
            evidence: input.currentText,
            severity: severity,
            scope: scope,
            fixLevel: fixLevel,
            suggestedFix: nil,
            startOffset: nil,
            endOffset: nil
        )]
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

struct OneLineParagraphsRule: ProseRule {
    let id = "rhythm.oneLineParagraphs"
    let title = "Excessive one-line paragraphs"
    let scope: RuleScope = .document
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let paragraphs = TextUtilities.splitParagraphs(input.document.plainText)
        let oneLiners = paragraphs.filter { TextUtilities.wordCount($0) <= 8 }.count
        guard paragraphs.count > 5, Double(oneLiners) / Double(paragraphs.count) > 0.45 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Many one-line paragraphs (\(oneLiners)/\(paragraphs.count)).",
            evidence: "\(oneLiners) short paragraphs",
            severity: severity,
            scope: scope,
            fixLevel: fixLevel,
            suggestedFix: nil,
            startOffset: nil,
            endOffset: nil
        )]
    }

    func fix(input: FixInput) -> FixResult? { nil }
}
