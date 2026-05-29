import Foundation

// MARK: - Repetition (extended)

struct RepeatedWordsAcrossParagraphsRule: ProseRule {
    let id = "repetition.words.nearby"
    let title = "Repeated words across nearby paragraphs"
    let scope: RuleScope = .paragraphWindow
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let texts = [input.previousText, input.currentText, input.nextText].compactMap { $0 }
        guard texts.count >= 2 else { return [] }
        var global: [String: Int] = [:]
        for text in texts {
            for w in text.lowercased().split(whereSeparator: { !$0.isLetter }) where w.count > 4 {
                global[String(w), default: 0] += 1
            }
        }
        return global.filter { $0.value >= 4 }.prefix(3).map { word, count in
            RuleViolation(
                id: "\(id).\(word)",
                title: title,
                message: "Word \"\(word)\" appears \(count)× across adjacent paragraphs.",
                evidence: word,
                severity: severity,
                scope: scope,
                fixLevel: fixLevel,
                suggestedFix: nil,
                startOffset: nil,
                endOffset: nil
            )
        }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

struct RepeatedPhraseFragmentRule: ProseRule {
    let id = "repetition.phraseFragment"
    let title = "Repeated phrase fragment"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let words = input.currentText.lowercased().split { !$0.isLetter }.map(String.init)
        guard words.count >= 6 else { return [] }
        var seen: [String: Int] = [:]
        for i in 0..<(words.count - 2) {
            let phrase = words[i...i+2].joined(separator: " ")
            if phrase.count >= 10 { seen[phrase, default: 0] += 1 }
        }
        return seen.filter { $0.value >= 2 }.prefix(2).map { phrase, count in
            RuleViolation(
                id: "\(id).\(phrase.hashValue)",
                title: title,
                message: "Phrase \"\(phrase)\" repeats \(count)× in paragraph.",
                evidence: phrase,
                severity: severity,
                scope: scope,
                fixLevel: fixLevel,
                suggestedFix: nil,
                startOffset: nil,
                endOffset: nil
            )
        }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

struct RepeatedGesturePatternRule: ProseRule {
    let id = "repetition.gesture"
    let title = "Repeated gesture pattern"
    let scope: RuleScope = .scene
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    private let gestures = ["зітхнув", "посміхнувся", "кивнув", "пожав плечима", "зморщив", "sigh", "smiled", "nodded", "shrugged"]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        let hits = gestures.filter { lowered.contains($0) }
        guard hits.count >= 2 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Multiple gesture beats in scene: \(hits.joined(separator: ", ")).",
            evidence: hits.joined(separator: ", "),
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

// MARK: - Atmosphere

struct GenericSensoryOveruseRule: ProseRule {
    let id = "atmosphere.sensoryOveruse"
    let title = "Generic sensory token overuse"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    private let tokens = ["запах", "аромат", "smell", "scent", "темрява", "darkness", "тиша", "silence", "холод", "cold"]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        let count = tokens.reduce(0) { $0 + (lowered.components(separatedBy: $1).count - 1) }
        guard count >= 3 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Dense generic sensory tokens (\(count) hits). Consider specificity.",
            evidence: input.currentText.prefix(120).description,
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

struct AtmosphereVocabularyRepetitionRule: ProseRule {
    let id = "atmosphere.vocabularyRepeat"
    let title = "Repeated atmosphere vocabulary"
    let scope: RuleScope = .chapter
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    private let moodWords = ["напруга", "тривога", "страх", "темно", "важко", "tension", "dread", "fear", "dark", "heavy"]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        let hits = moodWords.filter { lowered.contains($0) }
        guard hits.count >= 4 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Atmosphere vocabulary may be overused in chapter: \(hits.prefix(4).joined(separator: ", ")).",
            evidence: hits.joined(separator: ", "),
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

// MARK: - Language

struct SuspiciousCalqueRule: ProseRule {
    let id = "language.calque"
    let title = "Suspicious calque / russism"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .suggestedFix

    private let calques: [(String, String)] = [
        ("на даний момент", "зараз"),
        ("в принципі", "загалом"),
        ("як би", ""),
        ("по факту", "насправді"),
        ("відносно", "порівняно з")
    ]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        return calques.compactMap { calque, suggestion -> RuleViolation? in
            guard lowered.contains(calque) else { return nil }
            return RuleViolation(
                id: "\(id).\(calque.hashValue)",
                title: title,
                message: "Possible calque: \"\(calque)\".",
                evidence: calque,
                severity: severity,
                scope: scope,
                fixLevel: fixLevel,
                suggestedFix: suggestion.isEmpty ? nil : input.currentText.replacingOccurrences(of: calque, with: suggestion, options: .caseInsensitive),
                startOffset: nil,
                endOffset: nil
            )
        }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

struct TerminologyMismatchRule: ProseRule {
    let id = "language.terminology"
    let title = "Terminology inconsistency"
    let scope: RuleScope = .document
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        var violations: [RuleViolation] = []
        for entity in input.canon where entity.type == .term {
            let alt = entity.aliases.filter { !$0.isEmpty }
            for alias in alt {
                if input.currentText.contains(alias) && !input.currentText.contains(entity.name) {
                    violations.append(RuleViolation(
                        id: "\(id).\(entity.id)",
                        title: title,
                        message: "Alias \"\(alias)\" used; preferred term is \"\(entity.name)\".",
                        evidence: alias,
                        severity: severity,
                        scope: scope,
                        fixLevel: .suggestedFix,
                        suggestedFix: entity.name,
                        startOffset: nil,
                        endOffset: nil
                    ))
                }
            }
        }
        return violations.prefix(5).map { $0 }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

// MARK: - Causality / continuity

struct ObjectContinuityRule: ProseRule {
    let id = "causality.objectContinuity"
    let title = "Object used without introduction"
    let scope: RuleScope = .paragraphWindow
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let objects = input.canon.filter { $0.type == .object }.map(\.name) + input.canon.flatMap(\.activeObjectsFromFacts)
        guard !objects.isEmpty else { return [] }
        let prev = (input.previousText ?? "").lowercased()
        let cur = input.currentText.lowercased()
        return objects.compactMap { name -> RuleViolation? in
            let key = name.lowercased()
            guard cur.contains(key), !prev.contains(key) else { return nil }
            return RuleViolation(
                id: "\(id).\(key)",
                title: title,
                message: "Object \"\(name)\" appears without mention in previous paragraph.",
                evidence: name,
                severity: severity,
                scope: scope,
                fixLevel: fixLevel,
                suggestedFix: nil,
                startOffset: nil,
                endOffset: nil
            )
        }.prefix(3).map { $0 }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

private extension CanonEntity {
    var activeObjectsFromFacts: [String] {
        facts.filter { $0.localizedCaseInsensitiveContains("object") || $0.localizedCaseInsensitiveContains("предмет") }
    }
}

// MARK: - Structure

struct SceneMissingPressureRule: ProseRule {
    let id = "structure.scenePressure"
    let title = "Scene may lack pressure change"
    let scope: RuleScope = .scene
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    private let pressureSignals = ["але", "однак", "раптом", "натомість", "загроз", "небезп", "ризик", "but", "however", "suddenly", "threat", "risk"]

    func detect(input: RuleInput) -> [RuleViolation] {
        guard let scene = input.scene, !scene.function.isEmpty else { return [] }
        let lowered = input.currentText.lowercased()
        let hasPressure = pressureSignals.contains { lowered.contains($0) }
        guard !hasPressure, input.currentText.count > 400 else { return [] }
        return [RuleViolation(
            id: "\(id).\(scene.id)",
            title: title,
            message: "Scene \"\(scene.title)\" has function set but few pressure-shift signals.",
            evidence: scene.function,
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

struct RepeatedChapterSceneShapeRule: ProseRule {
    let id = "structure.repeatedSceneShape"
    let title = "Repeated scene shapes in chapter"
    let scope: RuleScope = .chapter
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        guard let chapter = input.chapter else { return [] }
        let scenes = input.editRules.isEmpty ? [] : [] // use structure via scene functions in text heuristic
        _ = scenes
        let functions = input.currentText.components(separatedBy: "***").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }
        let similarLengths = functions.filter { $0 > 100 }
        guard similarLengths.count >= 3 else { return [] }
        let avg = similarLengths.reduce(0, +) / similarLengths.count
        let uniform = similarLengths.filter { abs($0 - avg) < avg / 4 }.count
        guard uniform >= 3 else { return [] }
        return [RuleViolation(
            id: "\(id).\(chapter.id)",
            title: title,
            message: "Chapter may repeat similar scene lengths/shapes (\(uniform) segments).",
            evidence: chapter.title,
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

struct DialogueSymmetryRule: ProseRule {
    let id = "dialogue.symmetry"
    let title = "Dialogue exchange symmetry"
    let scope: RuleScope = .scene
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let lines = input.currentText.components(separatedBy: "\n").filter { $0.contains("—") || $0.contains("\"") || $0.contains("«") }
        guard lines.count >= 6 else { return [] }
        let lengths = lines.map { $0.count }
        let avg = lengths.reduce(0, +) / lengths.count
        let uniform = lengths.filter { abs($0 - avg) < max(8, avg / 5) }.count
        guard Double(uniform) / Double(lines.count) > 0.75 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Dialogue lines are unusually uniform in length (\(lines.count) lines).",
            evidence: "\(lines.count) dialogue lines",
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

struct EscalationStagnationRule: ProseRule {
    let id = "narrative.escalationStagnation"
    let title = "Pacing stagnation / repeated escalation"
    let scope: RuleScope = .document
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    private let escalation = ["нарешті", "раптом", "крича", "вибух", "finally", "suddenly", "scream", "explod"]

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        let count = escalation.reduce(0) { $0 + (lowered.components(separatedBy: $1).count - 1) }
        guard count >= 8 else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Document has many escalation beats (\(count)); possible stagnation pattern.",
            evidence: "escalation hits: \(count)",
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

struct NarrativeRepetitionMotifRule: ProseRule {
    let id = "narrative.repeatedMotif"
    let title = "Overused motif / vocabulary"
    let scope: RuleScope = .document
    let severity: RuleSeverity = .info
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let words = input.currentText.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 5 }
        var counts: [String: Int] = [:]
        for w in words { counts[w, default: 0] += 1 }
        return counts.filter { $0.value >= 25 }.prefix(3).map { word, count in
            RuleViolation(
                id: "\(id).\(word)",
                title: title,
                message: "Motif/word \"\(word)\" appears \(count)× in document.",
                evidence: word,
                severity: severity,
                scope: scope,
                fixLevel: fixLevel,
                suggestedFix: nil,
                startOffset: nil,
                endOffset: nil
            )
        }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}
