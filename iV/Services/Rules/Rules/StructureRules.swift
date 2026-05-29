import Foundation

struct SceneMissingFunctionRule: ProseRule {
    let id = "structure.sceneFunction"
    let title = "Scene missing function metadata"
    let scope: RuleScope = .scene
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        guard let scene = input.scene else { return [] }
        guard scene.function.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Scene \"\(scene.title)\" has no function metadata.",
            evidence: scene.title,
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

struct MoodWithoutActionRule: ProseRule {
    let id = "atmosphere.moodWithoutAction"
    let title = "Mood without action/perception/consequence"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        let moodTokens = ["dark", "heavy", "quiet", "cold", "тьм", "важк", "тих", "холод"]
        let actionTokens = ["walk", "run", "grab", "open", "close", "йш", "біг", "схоп", "відкри", "закри"]
        let hasMood = moodTokens.contains { lowered.contains($0) }
        let hasAction = actionTokens.contains { lowered.contains($0) }
        guard hasMood, !hasAction else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Atmosphere/mood may not connect to action or consequence.",
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
