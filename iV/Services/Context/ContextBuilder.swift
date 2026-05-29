import Foundation

struct ContextBuilder: Sendable {
    func build(
        task: String,
        scope: RuleScope,
        document: Document,
        index: DocumentIndex,
        paragraphID: UUID?,
        structure: DocumentStructure,
        memory: [NarrativeMemory],
        canon: [CanonEntity],
        ruleFiles: [EditRuleFile],
        categories: [EditRuleCategory],
        diagnostics: [Diagnostic]
    ) -> ContextPacket {
        let paragraphs = index.paragraphs.map(\.paragraph)
        let currentParagraph = paragraphID.flatMap { id in paragraphs.first { $0.id == id } }
        let order = currentParagraph?.order ?? 0
        let previous = order > 0 ? paragraphs[safe: order - 1]?.text : nil
        let next = paragraphs[safe: order + 1]?.text
        let currentText = currentParagraph?.text ?? document.plainText

        let scene = structure.scenes.first { scene in
            guard let pid = paragraphID else { return false }
            guard let start = scene.startParagraphID else { return false }
            let startOrder = paragraphs.firstIndex { $0.id == start } ?? 0
            let endOrder = scene.endParagraphID.flatMap { endID in paragraphs.firstIndex { $0.id == endID } } ?? (paragraphs.count - 1)
            guard let targetOrder = paragraphs.firstIndex(where: { $0.id == pid }) else { return false }
            return targetOrder >= startOrder && targetOrder <= endOrder
        }
        let chapter = structure.chapters.first { chapter in
            structure.scenes.contains { $0.chapterID == chapter.id && $0.id == scene?.id }
        }
        let previousScene: Scene? = {
            guard let scene else { return nil }
            return structure.scenes
                .filter { $0.chapterID == scene.chapterID && $0.order < scene.order }
                .sorted { $0.order > $1.order }
                .first
        }()

        let sceneSummary = scene?.summary.isEmpty == false ? scene?.summary : memory.first { $0.scope == .scene && $0.scopeID == scene?.id }?.summary
        let previousSceneSummary = previousScene.map { ps in
            ps.summary.isEmpty ? (memory.first { $0.scope == .scene && $0.scopeID == ps.id }?.summary ?? "") : ps.summary
        }.flatMap { $0.isEmpty ? nil : $0 }
        let chapterSummary = chapter?.summary.isEmpty == false ? chapter?.summary : memory.first { $0.scope == .chapter && $0.scopeID == chapter?.id }?.summary
        let documentSummary = memory.first { $0.scope == .document && $0.scopeID == document.id }?.summary
        let projectMemory = memory.first { $0.scope == .project }?.summary

        var categories = categories
        if !categories.contains(.minimumGate) {
            categories.insert(.minimumGate, at: 0)
        }

        let relevantCanon = canon.filter { entity in
            currentText.localizedCaseInsensitiveContains(entity.name) ||
            entity.aliases.contains { currentText.localizedCaseInsensitiveContains($0) }
        }

        let projectMem = memory.first { $0.scope == .project }

        return ContextPacket(
            task: task,
            scope: scope,
            currentText: currentText,
            previousText: previous,
            nextText: next,
            sceneSummary: sceneSummary,
            previousSceneSummary: previousSceneSummary,
            chapterSummary: chapterSummary,
            documentSummary: documentSummary,
            projectMemory: projectMemory,
            relevantEditRules: EditRuleExcerptBuilder.excerpts(from: ruleFiles, categories: categories),
            relevantCanon: relevantCanon,
            activeObjects: projectMem?.activeObjects ?? [],
            characterStates: projectMem?.characterStates ?? [],
            openThreads: projectMem?.openThreads ?? [],
            existingDiagnostics: diagnostics.filter { !$0.isStale && $0.paragraphID == paragraphID }
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum RelevantRuleSelector {
    static func categories(for passID: String) -> [EditRuleCategory] {
        switch passID {
        case "minimum-gate": return [.minimumGate]
        case "rhythm": return [.styleLineControl, .coreProse]
        case "dialogue": return [.dialogue, .characterVoice, .causalityPOVLogic]
        case "causality": return [.causalityPOVLogic, .coreProse]
        case "atmosphere": return [.atmosphereSensory]
        case "language": return [.canonLanguage]
        case "action": return [.actionAftermath]
        case "world": return [.worldInformation]
        default: return [.minimumGate]
        }
    }
}
