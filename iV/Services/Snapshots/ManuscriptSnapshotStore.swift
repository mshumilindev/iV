import Foundation

enum ManuscriptSnapshotStore {
    static let maxSnapshotsPerDocument = 30

    @discardableResult
    static func createSnapshot(
        projectID: UUID,
        document: Document,
        folder: URL,
        reason: ManuscriptSnapshotReason,
        chapterID: UUID? = nil,
        note: String? = nil,
        protect: Bool? = nil
    ) throws -> ManuscriptSnapshotRecord {
        let record = ManuscriptSnapshotRecord(
            id: UUID(),
            projectID: projectID,
            documentID: document.id,
            chapterID: chapterID,
            plainText: document.plainText,
            contentFormatVersion: ManuscriptSnapshotRecord.contentFormatVersion,
            createdAt: Date(),
            reason: reason,
            wordCount: TextUtilities.wordCount(document.plainText),
            schemaVersion: ManuscriptSnapshotRecord.schemaVersion,
            note: note,
            isProtected: protect ?? (reason == .beforeDestructiveAction)
        )
        var index = try loadIndex(documentID: document.id, folder: folder)
        index.snapshots.insert(record, at: 0)
        index.snapshots = applyRetention(index.snapshots)
        try saveIndex(index, folder: folder)
        try AtomicFileWriter.write(record, to: ProjectPaths.documentSnapshotURL(folder: folder, documentID: document.id, snapshotID: record.id))
        return record
    }

    static func listSnapshots(documentID: UUID, folder: URL) throws -> [ManuscriptSnapshotRecord] {
        try loadIndex(documentID: documentID, folder: folder).snapshots
    }

    static func loadSnapshot(id: UUID, documentID: UUID, folder: URL) throws -> ManuscriptSnapshotRecord {
        let url = ProjectPaths.documentSnapshotURL(folder: folder, documentID: documentID, snapshotID: id)
        return try AtomicFileWriter.read(ManuscriptSnapshotRecord.self, from: url)
    }

    static func deleteSnapshots(documentID: UUID, folder: URL) throws {
        let dir = ProjectPaths.documentSnapshotsFolder(folder: folder, documentID: documentID)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private static func loadIndex(documentID: UUID, folder: URL) throws -> ManuscriptSnapshotIndex {
        let url = ProjectPaths.documentSnapshotsIndexURL(folder: folder, documentID: documentID)
        let dir = ProjectPaths.documentSnapshotsFolder(folder: folder, documentID: documentID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ManuscriptSnapshotIndex(documentID: documentID)
        }
        return try AtomicFileWriter.read(ManuscriptSnapshotIndex.self, from: url)
    }

    private static func saveIndex(_ index: ManuscriptSnapshotIndex, folder: URL) throws {
        try AtomicFileWriter.write(index, to: ProjectPaths.documentSnapshotsIndexURL(folder: folder, documentID: index.documentID))
    }

    static func applyRetention(_ snapshots: [ManuscriptSnapshotRecord]) -> [ManuscriptSnapshotRecord] {
        guard snapshots.count > maxSnapshotsPerDocument else { return snapshots }
        var sorted = snapshots.sorted { $0.createdAt > $1.createdAt }
        var kept: [ManuscriptSnapshotRecord] = []
        var protected = sorted.filter(\.isProtected)
        var regular = sorted.filter { !$0.isProtected }
        for item in protected {
            if !kept.contains(where: { $0.id == item.id }) { kept.append(item) }
        }
        for item in regular {
            guard kept.count < maxSnapshotsPerDocument else { break }
            kept.append(item)
        }
        if kept.count > maxSnapshotsPerDocument {
            kept = Array(kept.prefix(maxSnapshotsPerDocument))
        }
        return kept.sorted { $0.createdAt > $1.createdAt }
    }
}
