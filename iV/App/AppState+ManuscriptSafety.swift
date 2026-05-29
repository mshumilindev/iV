import Foundation
import SwiftUI

extension AppState {
    var activeScene: Scene? {
        SceneIndexService.activeScene(
            cursorLocation: selectionLocation,
            index: documentIndex,
            structure: structure
        )
    }

    var activeSceneStatusLine: String {
        guard let doc = activeDocument else { return "" }
        let chapter = structure.chapters.first { ch in
            guard let pid = selectedParagraphID else { return false }
            return ch.startParagraphID == pid || ch.endParagraphID == pid
        } ?? structure.chapters.first
        let scene = activeScene
        let chTitle = chapter?.title ?? "Manuscript"
        let scTitle = scene?.title ?? "Scene"
        let words = scene?.wordCount ?? TextUtilities.wordCount(doc.plainText)
        return "\(chTitle) · \(scTitle) · \(words) words"
    }

    func bumpEditorContentEpoch() {
        editorContentEpoch += 1
    }

    func createSafetySnapshot(reason: ManuscriptSnapshotReason, note: String? = nil) {
        guard let project = currentProject, let document = activeDocument, let folder = currentFolder else { return }
        do {
            _ = try ManuscriptSnapshotStore.createSnapshot(
                projectID: project.id,
                document: document,
                folder: folder,
                reason: reason,
                note: note
            )
        } catch {
            reportPersistenceFailure("Snapshot", error)
        }
    }

    func createManualSnapshot(note: String?) {
        createSafetySnapshot(reason: .manual, note: note)
        statusMessage = "Checkpoint saved"
    }

    func restoreSnapshot(_ record: ManuscriptSnapshotRecord) {
        guard var document = activeDocument, let folder = currentFolder, let project = currentProject else { return }
        createSafetySnapshot(reason: .beforeDestructiveAction, note: "Before restore")
        document.plainText = record.plainText
        document.updatedAt = Date()
        do {
            try documentStore.save(document, folder: folder)
            loadDocument(document)
            bumpEditorContentEpoch()
            statusMessage = "Restored snapshot from \(record.createdAt.formatted())"
        } catch {
            documentSaveState = .saveError
            reportPersistenceFailure("Restore snapshot", error)
        }
        _ = project
    }

    func rerunSceneDetection() {
        guard activeDocument != nil else { return }
        createSafetySnapshot(reason: .beforeSceneReindex)
        isRerunSceneDetection = true
        rebuildStructureNow(preserveManual: true)
        isRerunSceneDetection = false
        statusMessage = "Scene index updated"
    }

    func markSceneIndexReviewed() {
        structure.sceneIndex?.status = .clean
        structure.sceneIndex?.reviewedAt = Date()
        for i in structure.scenes.indices where structure.scenes[i].indexStatus == .needsReview {
            structure.scenes[i].indexStatus = .clean
        }
        persistStructureIfNeeded()
        statusMessage = "Scene index marked reviewed"
    }

    func renameScene(_ sceneID: UUID, title: String) {
        guard let idx = structure.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        structure.scenes[idx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        structure.scenes[idx].isManualBoundary = true
        structure.scenes[idx].boundarySource = .manual
        structure.scenes[idx].indexStatus = .userCorrected
        structure.scenes[idx].updatedAt = Date()
        persistStructureIfNeeded()
    }

    func splitSceneAtCursor() {
        guard var document = activeDocument, let index = documentIndex else { return }
        createSafetySnapshot(reason: .beforeDestructiveAction, note: "Before split scene")
        let loc = min(selectionLocation, document.plainText.count)
        let insert = "\n\n***\n\n"
        let str = document.plainText
        let start = str.index(str.startIndex, offsetBy: loc)
        document.plainText = String(str[..<start]) + insert + String(str[start...])
        activeDocument = document
        bumpEditorContentEpoch()
        onEditorTextChange(document.plainText)
        if let scene = structure.scenes.first(where: { $0.startParagraphID == selectedParagraphID }) {
            renameScene(scene.id, title: scene.title)
        }
        statusMessage = "Scene break inserted at cursor"
        _ = index
    }

    func mergeSceneWithPrevious(_ sceneID: UUID) {
        mergeSceneBoundary(sceneID: sceneID, withNext: false)
    }

    func mergeSceneWithNext(_ sceneID: UUID) {
        mergeSceneBoundary(sceneID: sceneID, withNext: true)
    }

    private func mergeSceneBoundary(sceneID: UUID, withNext: Bool) {
        guard let idx = structure.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        let partnerIndex = withNext ? idx + 1 : idx - 1
        guard structure.scenes.indices.contains(partnerIndex) else { return }
        let keep = withNext ? structure.scenes[idx] : structure.scenes[partnerIndex]
        let remove = withNext ? structure.scenes[partnerIndex] : structure.scenes[idx]
        structure.scenes.removeAll { $0.id == remove.id }
        if let end = remove.endParagraphID {
            structure.scenes[structure.scenes.firstIndex(where: { $0.id == keep.id })!].endParagraphID = end
        }
        structure.scenes[structure.scenes.firstIndex(where: { $0.id == keep.id })!].isManualBoundary = true
        structure.scenes[structure.scenes.firstIndex(where: { $0.id == keep.id })!].indexStatus = .userCorrected
        for i in structure.scenes.indices {
            structure.scenes[i].order = i
        }
        persistStructureIfNeeded()
        reindexDocument()
        statusMessage = "Scene boundary removed (text preserved)"
    }

    func persistStructureIfNeeded() {
        guard let docID = activeDocument?.id, let folder = currentFolder else { return }
        persistStructureBestEffort(documentID: docID, folder: folder)
    }

    func rebuildStructureNow(preserveManual: Bool = false) {
        guard let document = activeDocument, let index = documentIndex else { return }
        var paragraphs = index.paragraphs.map(\.paragraph)
        let built = SceneIndexService.build(
            documentID: document.id,
            paragraphs: paragraphs,
            plainText: document.plainText,
            existing: structure,
            preserveManualBoundaries: preserveManual
        )
        structure = built.structure
        paragraphs = built.updatedParagraphs
        documentIndex = DocumentIndex(
            documentID: index.documentID,
            paragraphs: zip(index.paragraphs, paragraphs).map { indexed, paragraph in
                IndexedParagraph(paragraph: paragraph, rangeStart: indexed.rangeStart, rangeEnd: indexed.rangeEnd)
            },
            updatedAt: Date()
        )
        if let folder = currentFolder {
            persistIndexBestEffort(documentIndex!, folder: folder)
            persistStructureBestEffort(documentID: document.id, folder: folder)
        }
    }
}
