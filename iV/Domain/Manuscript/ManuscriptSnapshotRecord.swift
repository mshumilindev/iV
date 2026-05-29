import Foundation

struct ManuscriptSnapshotRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var documentID: UUID
    var chapterID: UUID?
    var plainText: String
    var contentFormatVersion: Int
    var createdAt: Date
    var reason: ManuscriptSnapshotReason
    var wordCount: Int
    var schemaVersion: Int
    var note: String?
    var isProtected: Bool

    static let contentFormatVersion = 1
    static let schemaVersion = 1
}

struct ManuscriptSnapshotIndex: Codable, Sendable {
    var schemaVersion: Int
    var documentID: UUID
    var snapshots: [ManuscriptSnapshotRecord]

    static let schemaVersion = 1

    init(documentID: UUID, snapshots: [ManuscriptSnapshotRecord] = []) {
        self.schemaVersion = Self.schemaVersion
        self.documentID = documentID
        self.snapshots = snapshots
    }
}
