import Foundation

/// Runs deterministic analysis with mandatory gradual scope expansion.
struct AnalysisCoordinator: Sendable {
    private let engine = DeterministicRuleEngine.default

    struct RunResult: Sendable {
        var diagnostics: [Diagnostic]
        var scopesRun: [RuleScope]
    }

    func runExpandedAnalysis(
        project: Project,
        document: Document,
        index: DocumentIndex,
        structure: DocumentStructure,
        canon: [CanonEntity],
        ruleFiles: [EditRuleFile],
        paragraphID: UUID?,
        selectionText: String? = nil,
        maxScope: RuleScope = .chapter
    ) -> RunResult {
        let paragraphs = index.paragraphs.map(\.paragraph)
        guard !paragraphs.isEmpty else { return RunResult(diagnostics: [], scopesRun: []) }

        let targetOrder = paragraphs.firstIndex { $0.id == paragraphID } ?? 0
        let target = paragraphs[targetOrder]

        var allScopes: [RuleScope] = []
        var allDiagnostics: [Diagnostic] = []
        let expansion = ScopeResolver.expansionOrder(startingAt: .selection)
        let maxIndex = expansion.firstIndex(of: maxScope) ?? expansion.count - 1
        let trimmedSelection = selectionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSelection = !(trimmedSelection ?? "").isEmpty

        for scope in expansion.prefix(maxIndex + 1) {
            if scope == .selection, !hasSelection { continue }
            allScopes.append(scope)
            let input = makeInput(
                scope: scope,
                project: project,
                document: document,
                paragraphs: paragraphs,
                targetOrder: targetOrder,
                target: target,
                structure: structure,
                canon: canon,
                ruleFiles: ruleFiles,
                selectionText: trimmedSelection
            )
            let violations = engine.run(input: input)
            let chapter = ManuscriptStructureBuilder.chapter(for: target.id, in: structure)
            let scene = ManuscriptStructureBuilder.scene(for: target.id, in: structure)
            var diags = engine.diagnostics(
                from: violations,
                projectID: project.id,
                documentID: document.id,
                paragraph: scope == .document || scope == .project ? nil : target,
                chapterID: chapter?.id,
                sceneID: scene?.id
            )
            if let indexed = index.paragraphs.first(where: { $0.paragraph.id == target.id }) {
                diags = DiagnosticOffsetMapper.enrich(diags, indexed: indexed)
            }
            allDiagnostics.append(contentsOf: diags)
        }

        return RunResult(diagnostics: deduplicate(allDiagnostics), scopesRun: allScopes)
    }

    private func makeInput(
        scope: RuleScope,
        project: Project,
        document: Document,
        paragraphs: [Paragraph],
        targetOrder: Int,
        target: Paragraph,
        structure: DocumentStructure,
        canon: [CanonEntity],
        ruleFiles: [EditRuleFile],
        selectionText: String? = nil
    ) -> RuleInput {
        let previous = targetOrder > 0 ? paragraphs[targetOrder - 1].text : nil
        let next = paragraphs.indices.contains(targetOrder + 1) ? paragraphs[targetOrder + 1].text : nil

        let currentText: String
        switch scope {
        case .selection:
            currentText = selectionText ?? target.text
        case .sentence:
            currentText = target.text
        case .paragraph, .paragraphWindow:
            if scope == .paragraphWindow, let prev = previous {
                currentText = prev + "\n\n" + target.text + (next.map { "\n\n" + $0 } ?? "")
            } else {
                currentText = target.text
            }
        case .scene, .previousSceneCurrentScene:
            let scene = ManuscriptStructureBuilder.scene(for: target.id, in: structure)
            currentText = paragraphsForScene(scene, paragraphs: paragraphs, structure: structure)
        case .chapter, .chapterSection, .previousChapterCurrentChapter:
            let chapter = ManuscriptStructureBuilder.chapter(for: target.id, in: structure)
            currentText = paragraphsForChapter(chapter, paragraphs: paragraphs)
        case .document, .project:
            currentText = document.plainText
        }

        return RuleInput(
            project: project,
            document: document,
            chapter: ManuscriptStructureBuilder.chapter(for: target.id, in: structure),
            scene: ManuscriptStructureBuilder.scene(for: target.id, in: structure),
            paragraph: target,
            currentText: currentText,
            previousText: previous,
            nextText: next,
            canon: canon,
            editRules: ruleFiles,
            scope: scope
        )
    }

    private func paragraphsForScene(_ scene: Scene?, paragraphs: [Paragraph], structure: DocumentStructure) -> String {
        guard let scene, let startID = scene.startParagraphID else { return paragraphs.map(\.text).joined(separator: "\n\n") }
        let startOrder = paragraphs.firstIndex { $0.id == startID } ?? 0
        let endOrder: Int
        if let endID = scene.endParagraphID, let end = paragraphs.firstIndex(where: { $0.id == endID }) {
            endOrder = end
        } else if let nextScene = structure.scenes.filter({ $0.chapterID == scene.chapterID && $0.order > scene.order }).sorted(by: { $0.order < $1.order }).first,
                  let nextStart = nextScene.startParagraphID,
                  let nextIdx = paragraphs.firstIndex(where: { $0.id == nextStart }) {
            endOrder = max(startOrder, nextIdx - 1)
        } else {
            endOrder = paragraphs.count - 1
        }
        return paragraphs[startOrder...endOrder].map(\.text).joined(separator: "\n\n")
    }

    private func paragraphsForChapter(_ chapter: Chapter?, paragraphs: [Paragraph]) -> String {
        guard let chapter, let startID = chapter.startParagraphID else { return paragraphs.map(\.text).joined(separator: "\n\n") }
        let startOrder = paragraphs.firstIndex { $0.id == startID } ?? 0
        let endOrder = chapter.endParagraphID.flatMap { endID in paragraphs.firstIndex { $0.id == endID } } ?? (paragraphs.count - 1)
        return paragraphs[startOrder...endOrder].map(\.text).joined(separator: "\n\n")
    }

    private func deduplicate(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
        var seen = Set<String>()
        return diagnostics.filter { d in
            let key = "\(d.title)|\(d.message)|\(d.paragraphID?.uuidString ?? "")|\(d.scope.rawValue)"
            return seen.insert(key).inserted
        }
    }
}

enum DiagnosticOffsetMapper {
    static func enrich(_ diagnostics: [Diagnostic], indexed: IndexedParagraph) -> [Diagnostic] {
        diagnostics.map { d in
            var copy = d
            if copy.startOffset == nil {
                copy.startOffset = indexed.rangeStart
                copy.endOffset = indexed.rangeEnd
            }
            return copy
        }
    }
}
