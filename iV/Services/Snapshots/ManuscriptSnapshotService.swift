import Foundation

/// Periodic and legacy flat-file safety copies — prefer `ManuscriptSnapshotStore` for indexed snapshots.
enum ManuscriptSnapshotService {
    private static let minimumInterval: TimeInterval = 5 * 60
    private static let wordCountDeltaThreshold = 120

    @MainActor
    private static var lastCheckpointAt: [UUID: Date] = [:]
    @MainActor
    private static var lastCheckpointWords: [UUID: Int] = [:]

    /// Archives imported/replaced text (flat file + indexed snapshot when project context provided).
    @discardableResult
    static func archiveImportSnapshot(
        text: String,
        documentID: UUID,
        folder: URL,
        label: String,
        projectID: UUID? = nil
    ) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = ProjectPaths.snapshotsFolder(in: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(documentID.uuidString)-\(label)-\(stamp).txt")
        try AtomicFileWriter.write(text: text, to: url)
        if let projectID {
            var doc = Document(
                id: documentID,
                projectID: projectID,
                title: "",
                type: .manuscript,
                plainText: text,
                originalSnapshot: nil,
                acceptedPlainText: nil,
                formattingSpans: nil,
                createdAt: Date(),
                updatedAt: Date(),
                version: PersistenceSchema.document
            )
            _ = try? ManuscriptSnapshotStore.createSnapshot(
                projectID: projectID,
                document: doc,
                folder: folder,
                reason: .beforeImport
            )
        }
        return url
    }

    @MainActor
    static func writeCheckpointIfDue(document: Document, projectID: UUID, folder: URL) {
        let words = TextUtilities.wordCount(document.plainText)
        let now = Date()
        if let last = lastCheckpointAt[document.id],
           now.timeIntervalSince(last) < minimumInterval,
           abs(words - (lastCheckpointWords[document.id] ?? 0)) < wordCountDeltaThreshold {
            return
        }
        do {
            _ = try ManuscriptSnapshotStore.createSnapshot(
                projectID: projectID,
                document: document,
                folder: folder,
                reason: .autosaveCheckpoint
            )
            lastCheckpointAt[document.id] = now
            lastCheckpointWords[document.id] = words
        } catch {
            // Best-effort; live JSON autosave remains authoritative.
        }
    }
}
