import Foundation

/// Scene index build, enrichment, manual preservation, and user corrections.
enum SceneIndexService {
    struct BuildResult: Sendable {
        var structure: DocumentStructure
        var updatedParagraphs: [Paragraph]
    }

    static func build(
        documentID: UUID,
        paragraphs: [Paragraph],
        plainText: String,
        existing: DocumentStructure,
        preserveManualBoundaries: Bool
    ) -> BuildResult {
        let blankGapStarts = SceneDetector.blankGapParagraphStarts(in: plainText, paragraphs: paragraphs)
        let raw = ManuscriptStructureBuilder.build(
            documentID: documentID,
            paragraphs: paragraphs,
            existing: existing,
            blankGapSceneStarts: blankGapStarts
        )
        var built = BuildResult(structure: raw.structure, updatedParagraphs: raw.updatedParagraphs)
        if preserveManualBoundaries {
            built = preserveManualScenes(
                built: built,
                existing: existing,
                paragraphs: paragraphs,
                plainText: plainText
            )
        }
        var structure = built.structure
        structure.scenes = enrichScenes(structure.scenes, paragraphs: built.updatedParagraphs)
        structure.sceneIndex = DocumentSceneIndexState(
            status: aggregateStatus(for: structure.scenes),
            detectionVersion: DocumentSceneIndexState.currentDetectionVersion,
            lastIndexedAt: Date(),
            reviewedAt: existing.sceneIndex?.reviewedAt
        )
        return BuildResult(structure: structure, updatedParagraphs: built.updatedParagraphs)
    }

    static func markStaleNearEdits(structure: inout DocumentStructure, dirtyParagraphIDs: Set<UUID>) {
        guard !dirtyParagraphIDs.isEmpty else { return }
        for i in structure.scenes.indices {
            guard let start = structure.scenes[i].startParagraphID else { continue }
            let end = structure.scenes[i].endParagraphID ?? start
            let affected = structure.scenes[i].indexStatus != .userCorrected
                && (dirtyParagraphIDs.contains(start) || dirtyParagraphIDs.contains(end))
            if affected {
                structure.scenes[i].indexStatus = .stale
            }
        }
        if structure.scenes.contains(where: { $0.indexStatus == .stale || $0.indexStatus == .needsReview }) {
            structure.sceneIndex?.status = .stale
        }
    }

    static func activeScene(
        cursorLocation: Int,
        index: DocumentIndex?,
        structure: DocumentStructure
    ) -> Scene? {
        guard let index else { return structure.scenes.first }
        guard let paragraph = index.paragraphs.first(where: { cursorLocation >= $0.rangeStart && cursorLocation < $0.rangeEnd })?.paragraph
            ?? index.paragraphs.last?.paragraph else {
            return structure.scenes.first
        }
        return structure.scenes.first { scene in
            guard let start = scene.startParagraphID else { return false }
            if start == paragraph.id { return true }
            guard let startOrder = index.paragraphs.first(where: { $0.paragraph.id == start })?.paragraph.order,
                  let pOrder = index.paragraphs.first(where: { $0.paragraph.id == paragraph.id })?.paragraph.order else {
                return false
            }
            if let end = scene.endParagraphID,
               let endOrder = index.paragraphs.first(where: { $0.paragraph.id == end })?.paragraph.order {
                return pOrder >= startOrder && pOrder <= endOrder
            }
            return pOrder >= startOrder
        } ?? ManuscriptStructureBuilder.scene(for: paragraph.id, in: structure)
    }

    private static func enrichScenes(_ scenes: [Scene], paragraphs: [Paragraph]) -> [Scene] {
        scenes.map { scene in
            var s = scene
            guard let start = s.startParagraphID else { return s }
            let metrics = SceneDetector.metrics(for: paragraphs, startID: start, endID: s.endParagraphID)
            s.wordCount = metrics.words
            s.characterCount = metrics.characters
            s.preview = SceneDetector.scenePreview(from: paragraphs, startID: start, endID: s.endParagraphID)
            if s.indexStatus == .clean, s.confidence < 0.6, !s.isManualBoundary {
                s.indexStatus = .needsReview
            }
            return s
        }
    }

    private static func aggregateStatus(for scenes: [Scene]) -> SceneIndexAggregateStatus {
        if scenes.contains(where: { $0.indexStatus == .stale }) { return .stale }
        if scenes.contains(where: { $0.indexStatus == .needsReview }) { return .needsReview }
        return .clean
    }

    private static func preserveManualScenes(
        built: BuildResult,
        existing: DocumentStructure,
        paragraphs: [Paragraph],
        plainText: String
    ) -> BuildResult {
        let manual = existing.scenes.filter(\.isManualBoundary)
        guard !manual.isEmpty else { return built }
        _ = plainText
        var scenes = built.structure.scenes
        for m in manual {
            if let idx = scenes.firstIndex(where: { $0.id == m.id }) {
                scenes[idx].title = m.title
                scenes[idx].isManualBoundary = true
                scenes[idx].boundarySource = .manual
                scenes[idx].indexStatus = .userCorrected
                scenes[idx].confidence = 1
            } else if let start = m.startParagraphID, paragraphs.contains(where: { $0.id == start }) {
                var restored = m
                restored.updatedAt = Date()
                scenes.append(restored)
            }
        }
        scenes.sort { $0.order < $1.order }
        var structure = built.structure
        structure.scenes = scenes
        return BuildResult(structure: structure, updatedParagraphs: built.updatedParagraphs)
    }
}
