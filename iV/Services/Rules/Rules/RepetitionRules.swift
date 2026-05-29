import Foundation

struct RepeatedWordsInParagraphRule: ProseRule {
    let id = "repetition.words.paragraph"
    let title = "Repeated words in paragraph"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let words = input.currentText.lowercased().split { !$0.isLetter }
        var counts: [String: Int] = [:]
        for w in words where w.count > 3 { counts[String(w), default: 0] += 1 }
        return counts.filter { $0.value >= 3 }.map { word, count in
            RuleViolation(
                id: "\(id).\(word)",
                title: title,
                message: "Word \"\(word)\" appears \(count) times in this paragraph.",
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

struct RepeatedSentenceOpeningsRule: ProseRule {
    let id = "repetition.sentenceOpenings"
    let title = "Repeated sentence openings"
    let scope: RuleScope = .paragraphWindow
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let combined = [input.previousText, input.currentText].compactMap { $0 }.joined(separator: "\n")
        let sentences = combined.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var openings: [String: Int] = [:]
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.split(separator: " ").first else { continue }
            let key = String(first).lowercased()
            if key.count > 2 { openings[key, default: 0] += 1 }
        }
        return openings.filter { $0.value >= 3 }.map { opening, count in
            RuleViolation(
                id: "\(id).\(opening)",
                title: title,
                message: "Sentences starting with \"\(opening)\" repeat nearby (\(count)×).",
                evidence: opening,
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

struct TriadicStructureRule: ProseRule {
    let id = "rhythm.triadic"
    let title = "Triadic AI-like structure"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let pattern = #"(?i)\b(\w+),\s+(\w+),\s+and\s+(\w+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(input.currentText.startIndex..., in: input.currentText)
        let matches = regex.matches(in: input.currentText, range: range)
        return matches.map { match in
            let evidence = (input.currentText as NSString).substring(with: match.range)
            return RuleViolation(
                id: "\(id).\(match.range.location)",
                title: title,
                message: "Possible triadic list structure detected.",
                evidence: evidence,
                severity: severity,
                scope: scope,
                fixLevel: fixLevel,
                suggestedFix: nil,
                startOffset: match.range.location,
                endOffset: match.range.location + match.range.length
            )
        }
    }

    func fix(input: FixInput) -> FixResult? { nil }
}

struct SymmetricalContrastRule: ProseRule {
    let id = "rhythm.symmetricalContrast"
    let title = "Symmetrical contrast pattern"
    let scope: RuleScope = .paragraph
    let severity: RuleSeverity = .warning
    let fixLevel: FixLevel = .humanOnly

    func detect(input: RuleInput) -> [RuleViolation] {
        let lowered = input.currentText.lowercased()
        guard lowered.contains("not ") && lowered.contains(" but ") else { return [] }
        return [RuleViolation(
            id: id,
            title: title,
            message: "Possible \"not X but Y\" symmetrical contrast.",
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
