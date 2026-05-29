import Foundation

enum ProjectPaths {
    static let projectExtension = "ivproject"

    static func applicationSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("iV", isDirectory: true)
    }

    static func globalRegistryURL() -> URL {
        if UITestSupport.isActive {
            return defaultProjectsRoot().appendingPathComponent("projects.json")
        }
        return applicationSupport().appendingPathComponent("projects.json")
    }

    /// Parent directory for new `.ivproject` folders (not the registry file).
    static func defaultProjectsRoot() -> URL {
        let url: URL
        if UITestSupport.isActive {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("iV-UITest-Projects", isDirectory: true)
        } else {
            url = applicationSupport().appendingPathComponent("Projects", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func embeddingsURL(folder: URL, documentID: UUID) -> URL {
        indexesFolder(in: folder).appendingPathComponent("\(documentID.uuidString)-embeddings.json")
    }

    static func projectFolder(name: String, parent: URL) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return parent.appendingPathComponent("\(safe).\(projectExtension)", isDirectory: true)
    }

    static func projectJSON(in folder: URL) -> URL { folder.appendingPathComponent("project.json") }
    static func manuscriptFolder(in folder: URL) -> URL { folder.appendingPathComponent("manuscript", isDirectory: true) }
    static func snapshotsFolder(in folder: URL) -> URL { folder.appendingPathComponent("snapshots", isDirectory: true) }
    static func coversFolder(in folder: URL) -> URL { folder.appendingPathComponent("covers", isDirectory: true) }
    static func exportsFolder(in folder: URL) -> URL { folder.appendingPathComponent("exports", isDirectory: true) }
    static func memoryFolder(in folder: URL) -> URL { folder.appendingPathComponent("memory", isDirectory: true) }
    static func diagnosticsFolder(in folder: URL) -> URL { folder.appendingPathComponent("diagnostics", isDirectory: true) }
    static func editRulesFolder(in folder: URL) -> URL { folder.appendingPathComponent("edit-rules", isDirectory: true) }
    static func indexesFolder(in folder: URL) -> URL { folder.appendingPathComponent("indexes", isDirectory: true) }

    static func documentURL(folder: URL, documentID: UUID) -> URL {
        manuscriptFolder(in: folder).appendingPathComponent("\(documentID.uuidString).json")
    }

    static func documentDocxURL(folder: URL, documentID: UUID) -> URL {
        manuscriptFolder(in: folder).appendingPathComponent("\(documentID.uuidString).docx")
    }

    static func documentIndexURL(folder: URL, documentID: UUID) -> URL {
        indexesFolder(in: folder).appendingPathComponent("\(documentID.uuidString)-paragraphs.json")
    }

    static func structureURL(folder: URL, documentID: UUID) -> URL {
        indexesFolder(in: folder).appendingPathComponent("\(documentID.uuidString)-structure.json")
    }

    static func canonURL(folder: URL) -> URL { memoryFolder(in: folder).appendingPathComponent("canon.json") }
    static func canonSuggestionsURL(folder: URL) -> URL { memoryFolder(in: folder).appendingPathComponent("canon-suggestions.json") }
    static func narrativeMemoryURL(folder: URL) -> URL { memoryFolder(in: folder).appendingPathComponent("narrative.json") }
    static func diagnosticsURL(folder: URL, documentID: UUID) -> URL {
        diagnosticsFolder(in: folder).appendingPathComponent("\(documentID.uuidString).json")
    }
    static func proposalsURL(folder: URL, documentID: UUID) -> URL {
        diagnosticsFolder(in: folder).appendingPathComponent("\(documentID.uuidString)-proposals.json")
    }
    static func analysisRunsURL(folder: URL) -> URL {
        diagnosticsFolder(in: folder).appendingPathComponent("analysis-runs.json")
    }
    static func acceptedManuscriptURL(folder: URL, documentID: UUID) -> URL {
        snapshotsFolder(in: folder).appendingPathComponent("\(documentID.uuidString)-accepted.txt")
    }
}

struct DocumentStructure: Codable, Sendable {
    var chapters: [Chapter]
    var scenes: [Scene]
    var sceneIndex: DocumentSceneIndexState?

    init(chapters: [Chapter], scenes: [Scene], sceneIndex: DocumentSceneIndexState? = nil) {
        self.chapters = chapters
        self.scenes = scenes
        self.sceneIndex = sceneIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapters = try c.decode([Chapter].self, forKey: .chapters)
        scenes = try c.decode([Scene].self, forKey: .scenes)
        sceneIndex = try c.decodeIfPresent(DocumentSceneIndexState.self, forKey: .sceneIndex)
    }

    enum CodingKeys: String, CodingKey {
        case chapters, scenes, sceneIndex
    }
}

extension ProjectPaths {
    static func documentSnapshotsFolder(folder: URL, documentID: UUID) -> URL {
        snapshotsFolder(in: folder)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    static func documentSnapshotsIndexURL(folder: URL, documentID: UUID) -> URL {
        documentSnapshotsFolder(folder: folder, documentID: documentID)
            .appendingPathComponent("index.json")
    }

    static func documentSnapshotURL(folder: URL, documentID: UUID, snapshotID: UUID) -> URL {
        documentSnapshotsFolder(folder: folder, documentID: documentID)
            .appendingPathComponent("\(snapshotID.uuidString).json")
    }
}
