import Foundation

struct LatinInUkrainianProseRule: ProseRule {
    let id = "language.latinInCyrillic"
    let title = "Latin script in Ukrainian prose"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .suggestedFix

    func detect(input: RuleInput) -> [RuleViolation] {
        guard TextUtilities.containsLatinInCyrillicContext(input.currentText) else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Mixed Latin and Cyrillic script detected.",
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

struct CanonSpellingRule: ProseRule {
    let id = "language.canonSpelling"
    let title = "Canon spelling mismatch"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .suggestedFix

    func detect(input: RuleInput) -> [RuleViolation] {
        var violations: [RuleViolation] = []
        for entity in input.canon where entity.type == .term || entity.type == .character {
            for alias in entity.aliases where !alias.isEmpty {
                if input.currentText.localizedCaseInsensitiveContains(alias),
                   !input.currentText.localizedCaseInsensitiveContains(entity.name) {
                    violations.append(RuleViolation(
                        id: "\(id).\(entity.id.uuidString)",
                        title: title,
                        message: "Found alias \"\(alias)\" but preferred name is \"\(entity.name)\".",
                        evidence: alias,
                        severity: severity,
                        scope: scope,
                        fixLevel: fixLevel,
                        suggestedFix: entity.name,
                        startOffset: nil,
                        endOffset: nil
                    ))
                }
            }
        }
        return violations
    }

    func fix(input: FixInput) -> FixResult? {
        guard let suggested = input.violation.suggestedFix else { return nil }
        let replaced = input.ruleInput.currentText.replacingOccurrences(of: input.violation.evidence, with: suggested, options: .caseInsensitive)
        return FixResult(replacement: replaced, description: "Replace with canon spelling")
    }
}

struct FalseAgencyRule: ProseRule {
    let id = "causality.falseAgency"
    let title = "False agency pattern"
    let scope: RuleScope = .sentence
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    private let subjects = ["city", "night", "silence", "rain", "room", "house", "міськ", "ніч", "тиша", "дощ", "кімнат", "будинок"]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        for subject in subjects where lowered.contains(subject) {
            if lowered.contains("\(subject) ") && (lowered.contains(" wanted ") || lowered.contains(" decided ") || lowered.contains(" wanted") || lowered.contains(" хотіл") || lowered.contains(" вирішил")) {
                return [RuleViolation(
                    id: "\(id).\(subject)",
                    title: title,
                    message: "Possible false agency for \"\(subject)\".",
                    evidence: input.currentText,
                    severity: severity,
                    scope: scope,
                    fixLevel: fixLevel,
                    suggestedFix: nil,
                    startOffset: nil,
                    endOffset: nil
                )]
            }
        }
        return []
    }

    func fix(input: FixInput) -> FixResult? { nil }
}
