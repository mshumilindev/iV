import Foundation

enum SceneBoundarySource: String, Codable, CaseIterable, Sendable {
    case manual
    case autoDetected
    case imported
    case separatorMarker
    case blankGap
    case aiSuggested
}

enum SceneRecordStatus: String, Codable, CaseIterable, Sendable {
    case clean
    case needsReview
    case stale
    case userCorrected
}

enum SceneIndexAggregateStatus: String, Codable, CaseIterable, Sendable {
    case clean
    case needsReview
    case stale
}

enum ManuscriptSnapshotReason: String, Codable, CaseIterable, Sendable {
    case manual
    case autosaveCheckpoint = "autosave_checkpoint"
    case beforeDestructiveAction = "before_destructive_action"
    case beforeBulkReplace = "before_bulk_replace"
    case beforeImport = "before_import"
    case beforeSceneReindex = "before_scene_reindex"
    case beforeRuleApply = "before_rule_apply"
    case recovery

    var displayName: String {
        switch self {
        case .manual: "Manual checkpoint"
        case .autosaveCheckpoint: "Autosave checkpoint"
        case .beforeDestructiveAction: "Before destructive action"
        case .beforeBulkReplace: "Before bulk replace"
        case .beforeImport: "Before import"
        case .beforeSceneReindex: "Before scene re-index"
        case .beforeRuleApply: "Before rule apply"
        case .recovery: "Recovery"
        }
    }
}

struct DocumentSceneIndexState: Codable, Hashable, Sendable {
    var status: SceneIndexAggregateStatus
    var detectionVersion: Int
    var lastIndexedAt: Date?
    var reviewedAt: Date?

    static let currentDetectionVersion = 1

    static var initial: DocumentSceneIndexState {
        DocumentSceneIndexState(
            status: .clean,
            detectionVersion: currentDetectionVersion,
            lastIndexedAt: nil,
            reviewedAt: nil
        )
    }
}
