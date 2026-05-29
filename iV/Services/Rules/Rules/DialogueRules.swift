import Foundation

struct DialogueWithoutTriggerRule: ProseRule {
    let id = "dialogue.noTrigger"
    let title = "Dialogue line without trigger"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let lines = input.currentText.components(separatedBy: "\n")
        var violations: [RuleViolation] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("—") || trimmed.hasPrefix("-") || trimmed.hasPrefix("\"") else { continue }
            let contextWords = ["said", "asked", "whispered", "murmured", "сказав", "прошепотів", "запитав"]
            let hasTrigger = contextWords.contains { input.currentText.localizedCaseInsensitiveContains($0) }
            if !hasTrigger {
                violations.append(RuleViolation(
                    id: "\(id).\(trimmed.hashValue)",
                    title: title,
                    message: "Dialogue line may lack a speech trigger.",
                    evidence: trimmed,
                    severity: severity,
                    scope: scope,
                    fixLevel: fixLevel,
                    suggestedFix: nil,
                    startOffset: nil,
                    endOffset: nil
                ))
            }
        }
        return violations
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

struct EmotionWithoutBehaviorRule: ProseRule {
    let id = "atmosphere.emotionWithoutBehavior"
    let title = "Emotion stated without behavior"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    private let emotionWords = ["sad", "angry", "afraid", "happy", "сумн", "злий", "бояв", "рад"]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        let hasEmotion = emotionWords.contains { lowered.contains($0) }
        let hasBehavior = ["trembl", "clench", "step", "look", "дриж", "стис", "крок", "подив"].contains { lowered.contains($0) }
        guard hasEmotion, !hasBehavior else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Emotion may be named without physical or behavioral support.",
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
