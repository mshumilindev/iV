import Foundation

struct DeterministicRuleEngine: Sendable {
    let rules: [any ProseRule]

    static let `default` = DeterministicRuleEngine(rules: [
        RepeatedWordsInParagraphRule(),
        RepeatedSentenceOpeningsRule(),
        TriadicStructureRule(),
        SymmetricalContrastRule(),
        ExcessiveShortSentencesRule(),
        OneLineParagraphsRule(),
        LatinInUkrainianProseRule(),
        CanonSpellingRule(),
        FalseAgencyRule(),
        DialogueWithoutTriggerRule(),
        EmotionWithoutBehaviorRule(),
        SceneMissingFunctionRule(),
        MoodWithoutActionRule(),
        RepeatedWordsAcrossParagraphsRule(),
        RepeatedPhraseFragmentRule(),
        RepeatedGesturePatternRule(),
        GenericSensoryOveruseRule(),
        AtmosphereVocabularyRepetitionRule(),
        SuspiciousCalqueRule(),
        TerminologyMismatchRule(),
        ObjectContinuityRule(),
        SceneMissingPressureRule(),
        RepeatedChapterSceneShapeRule(),
        DialogueSymmetryRule(),
        EscalationStagnationRule(),
        NarrativeRepetitionMotifRule()
    ])

    func run(input: RuleInput) -> [RuleViolation] {
        rules.flatMap { rule -> [RuleViolation] in
            guard shouldRun(rule: rule, at: input.scope) else { return [] }
            return rule.detect(input: input)
        }
    }

    private func shouldRun(rule: any ProseRule, at scope: RuleScope) -> Bool {
        if rule.scope == scope { return true }
        switch rule.scope {
        case .selection, .sentence, .paragraph:
            return [.selection, .sentence, .paragraph, .paragraphWindow, .scene, .chapter, .chapterSection].contains(scope)
        case .paragraphWindow:
            return [.paragraphWindow, .scene, .chapter].contains(scope)
        case .scene:
            return [.scene, .previousSceneCurrentScene, .chapter].contains(scope)
        case .document:
            return [.document, .project, .chapter].contains(scope)
        default:
            return rule.scope == scope
        }
    }

    func diagnostics(
        from violations: [RuleViolation],
        projectID: UUID,
        documentID: UUID,
        paragraph: Paragraph?,
        chapterID: UUID?,
        sceneID: UUID?
    ) -> [Diagnostic] {
        violations.map { v in
            Diagnostic(
                id: UUID(),
                projectID: projectID,
                documentID: documentID,
                chapterID: chapterID,
                sceneID: sceneID,
                paragraphID: paragraph?.id,
                ruleID: nil,
                source: .deterministic,
                severity: v.severity,
                scope: v.scope,
                title: v.title,
                message: v.message,
                evidence: DiagnosticEvidence.clamp(v.evidence, paragraphText: paragraph?.text),
                startOffset: v.startOffset,
                endOffset: v.endOffset,
                suggestedFix: v.suggestedFix,
                fixLevel: v.fixLevel,
                status: .open,
                textHashAtCreation: paragraph?.hash,
                scopeHashAtCreation: nil,
                isStale: false,
                staleReason: nil,
                createdAt: Date()
            )
        }
    }
}
