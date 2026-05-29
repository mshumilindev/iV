import Foundation

/// Infers chapters and scenes from manuscript text and links paragraph IDs.
enum ManuscriptStructureBuilder {
    struct BuildResult: Sendable {
        var structure: DocumentStructure
        var updatedParagraphs: [Paragraph]
    }

    static func build(
        documentID: UUID,
        paragraphs: [Paragraph],
        existing: DocumentStructure,
        blankGapSceneStarts: Set<UUID> = []
    ) -> BuildResult {
        guard !paragraphs.isEmpty else {
            return BuildResult(structure: existing, updatedParagraphs: paragraphs)
        }

        var chapters: [Chapter] = []
        var scenes: [Scene] = []
        var updated = paragraphs
        var chapterOrder = 0
        var sceneOrder = 0
        var currentChapterID: UUID?
        var currentSceneID: UUID?

        func startChapter(title: String, at paragraphID: UUID) {
            if let chID = currentChapterID, let idx = chapters.firstIndex(where: { $0.id == chID }) {
                chapters[idx].endParagraphID = paragraphID
            }
            let chapter = Chapter(
                id: UUID(),
                documentID: documentID,
                title: title,
                order: chapterOrder,
                summary: "",
                startParagraphID: paragraphID,
                endParagraphID: nil,
                diagnosticsSummary: .empty,
                createdAt: Date(),
                updatedAt: Date()
            )
            chapterOrder += 1
            chapters.append(chapter)
            currentChapterID = chapter.id
            sceneOrder = 0
            currentSceneID = nil
        }

        func startScene(
            title: String,
            at paragraphID: UUID,
            chapterID: UUID,
            source: SceneBoundarySource,
            confidence: Double,
            manual: Bool
        ) {
            if let scID = currentSceneID, let idx = scenes.firstIndex(where: { $0.id == scID }) {
                scenes[idx].endParagraphID = paragraphID
            }
            let scene = Scene(
                id: UUID(),
                chapterID: chapterID,
                title: title,
                order: sceneOrder,
                startParagraphID: paragraphID,
                boundarySource: source,
                confidence: confidence,
                indexStatus: confidence < 0.6 ? .needsReview : .clean,
                isManualBoundary: manual
            )
            sceneOrder += 1
            scenes.append(scene)
            currentSceneID = scene.id
        }

        for i in updated.indices {
            let text = updated[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let chapterTitle = detectChapterHeading(text) {
                startChapter(title: chapterTitle, at: updated[i].id)
                updated[i].chapterID = currentChapterID
                if let chID = currentChapterID {
                    startScene(title: "Opening", at: updated[i].id, chapterID: chID, source: .autoDetected, confidence: 1, manual: false)
                    updated[i].sceneID = currentSceneID
                }
                continue
            }

            let detection = SceneDetector.analyzeParagraph(text)
            let blankGap = blankGapSceneStarts.contains(updated[i].id)
            if detection.isBreak || blankGap {
                if currentChapterID == nil {
                    startChapter(title: "Chapter 1", at: updated[i].id)
                }
                if let chID = currentChapterID {
                    let sceneTitle = SceneDetector.detectSceneTitle(text) ?? "Scene \(sceneOrder + 1)"
                    let source: SceneBoundarySource = blankGap ? .blankGap : detection.source
                    let confidence = blankGap ? 0.55 : detection.confidence
                    startScene(title: sceneTitle, at: updated[i].id, chapterID: chID, source: source, confidence: confidence, manual: false)
                    updated[i].sceneID = currentSceneID
                    updated[i].chapterID = chID
                }
                continue
            }

            if currentChapterID == nil {
                startChapter(title: "Chapter 1", at: updated[i].id)
            }
            if currentChapterID != nil, currentSceneID == nil, let chID = currentChapterID {
                startScene(title: "Scene 1", at: updated[i].id, chapterID: chID, source: .autoDetected, confidence: 1, manual: false)
            }
            updated[i].chapterID = currentChapterID
            updated[i].sceneID = currentSceneID
        }

        if let chID = currentChapterID, let idx = chapters.firstIndex(where: { $0.id == chID }) {
            chapters[idx].endParagraphID = updated.last?.id
            chapters[idx].updatedAt = Date()
        }
        if let scID = currentSceneID, let idx = scenes.firstIndex(where: { $0.id == scID }) {
            scenes[idx].endParagraphID = updated.last?.id
            scenes[idx].updatedAt = Date()
        }

        if chapters.isEmpty {
            let chID = UUID()
            chapters.append(Chapter(
                id: chID,
                documentID: documentID,
                title: "Manuscript",
                order: 0,
                summary: "",
                startParagraphID: updated.first?.id,
                endParagraphID: updated.last?.id,
                diagnosticsSummary: .empty,
                createdAt: Date(),
                updatedAt: Date()
            ))
            let scID = UUID()
            scenes.append(Scene(
                id: scID,
                chapterID: chID,
                title: "Scene 1",
                order: 0,
                startParagraphID: updated.first?.id,
                endParagraphID: updated.last?.id,
                boundarySource: .autoDetected,
                confidence: 1
            ))
            for i in updated.indices {
                updated[i].chapterID = chID
                updated[i].sceneID = scID
            }
        }

        return BuildResult(
            structure: DocumentStructure(chapters: chapters, scenes: scenes),
            updatedParagraphs: updated
        )
    }

    static func detectChapterHeading(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("# ") { return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if trimmed.hasPrefix("## ") { return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        let chapterPattern = #"^(?i)(chapter|розділ|частина)\s+[\dIVXLC]+[\.:\-]?\s*(.*)$"#
        if let regex = try? NSRegularExpression(pattern: chapterPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let titleRange = match.range(at: 2)
            if titleRange.location != NSNotFound, let range = Range(titleRange, in: trimmed) {
                let subtitle = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                return subtitle.isEmpty ? trimmed : subtitle
            }
            return trimmed
        }
        if trimmed.count < 80, trimmed == trimmed.uppercased(), trimmed.contains(where: \.isLetter) {
            return trimmed
        }
        return nil
    }

    static func isSceneBreak(_ text: String) -> Bool {
        SceneDetector.analyzeParagraph(text).isBreak
    }

    static func scene(for paragraphID: UUID, in structure: DocumentStructure) -> Scene? {
        structure.scenes.first { scene in
            guard let start = scene.startParagraphID else { return false }
            if start == paragraphID { return true }
            if let end = scene.endParagraphID {
                return paragraphID == end
            }
            return false
        } ?? structure.scenes.first { $0.startParagraphID != nil }
    }

    static func chapter(for paragraphID: UUID, in structure: DocumentStructure) -> Chapter? {
        structure.chapters.first { ch in
            ch.startParagraphID == paragraphID || ch.endParagraphID == paragraphID
        } ?? structure.chapters.first
    }
}
