import Foundation

struct RuleInput: Sendable {
    var project: Project
    var document: Document
    var chapter: Chapter?
    var scene: Scene?
    var paragraph: Paragraph?
    var currentText: String
    var previousText: String?
    var nextText: String?
    var canon: [CanonEntity]
    var editRules: [EditRuleFile]
    var scope: RuleScope
}

struct FixInput: Sendable {
    var ruleInput: RuleInput
    var violation: RuleViolation
}

struct RuleViolation: Identifiable, Sendable {
    var id: String
    var title: String
    var message: String
    var evidence: String
    var severity: RuleSeverity
    var scope: RuleScope
    var fixLevel: FixLevel
    var suggestedFix: String?
    var startOffset: Int?
    var endOffset: Int?
}

struct FixResult: Sendable {
    var replacement: String
    var description: String
}

protocol ProseRule: Sendable {
    var id: String { get }
    var title: String { get }
    var scope: RuleScope { get }
    var severity: RuleSeverity { get }
    var fixLevel: FixLevel { get }

    func detect(input: RuleInput) -> [RuleViolation]
    func fix(input: FixInput) -> FixResult?
}
