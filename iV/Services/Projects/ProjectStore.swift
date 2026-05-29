import Foundation

enum ProjectStoreError: LocalizedError {
    case folderMissing
    case invalidProject

    var errorDescription: String? {
        switch self {
        case .folderMissing: "Project folder not found."
        case .invalidProject: "Invalid project data."
        }
    }
}

@MainActor
final class ProjectStore {
    func createProject(
        name: String,
        subtitle: String,
        parentFolder: URL,
        coverSourceURL: URL? = nil
    ) throws -> (Project, URL) {
        let folder = ProjectPaths.projectFolder(name: name, parent: parentFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for path in [
            ProjectPaths.manuscriptFolder, ProjectPaths.snapshotsFolder, ProjectPaths.coversFolder,
            ProjectPaths.exportsFolder, ProjectPaths.memoryFolder, ProjectPaths.diagnosticsFolder,
            ProjectPaths.editRulesFolder, ProjectPaths.indexesFolder
        ] {
            try FileManager.default.createDirectory(at: path(folder), withIntermediateDirectories: true)
        }

        var coverPath: String?
        if let coverSourceURL {
            coverPath = try copyCover(from: coverSourceURL, projectFolder: folder)
        }

        let project = Project(
            id: UUID(),
            name: name,
            subtitle: subtitle,
            rootURL: folder,
            createdAt: Date(),
            updatedAt: Date(),
            activeDocumentID: nil,
            settings: .default,
            enabledRuleFileIDs: [],
            ollamaSettings: .default,
            coverImagePath: coverPath,
            wordCount: 0,
            diagnosticsSummary: .empty,
            lastPipelineStatus: nil
        )

        try saveProject(project, folder: folder)
        _ = EditRuleLoader.copyBundledRulesToProject(folder: folder)
        let registryEntry = ProjectRegistryEntry(
            id: project.id,
            name: project.name,
            subtitle: project.subtitle,
            folderURL: folder,
            coverImagePath: coverPath,
            lastOpened: Date(),
            lastEdited: Date(),
            wordCount: 0,
            diagnosticsSummary: .empty,
            lastAnalysisStatus: nil
        )
        try ProjectRegistryService.shared.upsert(registryEntry)
        return (project, folder)
    }

    func openProject(folder: URL) throws -> Project {
        let projectURL = ProjectPaths.projectJSON(in: folder)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw ProjectStoreError.invalidProject
        }
        var project = try AtomicFileWriter.read(Project.self, from: projectURL)
        project.rootURL = folder
        return project
    }

    func saveProject(_ project: Project, folder: URL? = nil) throws {
        guard let folder = folder ?? project.rootURL else { throw ProjectStoreError.folderMissing }
        var updated = project
        updated.updatedAt = Date()
        updated.rootURL = folder
        try AtomicFileWriter.write(updated, to: ProjectPaths.projectJSON(in: folder))
        if var entry = ProjectRegistryService.shared.entry(for: project.id) {
            entry.name = updated.name
            entry.subtitle = updated.subtitle
            entry.lastEdited = updated.updatedAt
            entry.wordCount = updated.wordCount ?? entry.wordCount
            entry.diagnosticsSummary = updated.diagnosticsSummary
            entry.lastAnalysisStatus = updated.lastPipelineStatus
            entry.coverImagePath = updated.coverImagePath
            try ProjectRegistryService.shared.upsert(entry)
        }
    }

    func copyCover(from source: URL, projectFolder: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let dest = ProjectPaths.coversFolder(in: projectFolder).appendingPathComponent("cover.\(ext)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest.lastPathComponent
    }

    func updateProjectMetadata(
        folder: URL,
        projectID: UUID,
        name: String,
        subtitle: String,
        newCoverURL: URL? = nil,
        removeCover: Bool = false
    ) throws -> Project {
        var project = try openProject(folder: folder)
        guard project.id == projectID else { throw ProjectStoreError.invalidProject }
        project.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if removeCover, let existing = project.coverImagePath {
            let coverFile = ProjectPaths.coversFolder(in: folder).appendingPathComponent(existing)
            if FileManager.default.fileExists(atPath: coverFile.path) {
                try? FileManager.default.removeItem(at: coverFile)
            }
            project.coverImagePath = nil
        } else if let newCoverURL {
            project.coverImagePath = try copyCover(from: newCoverURL, projectFolder: folder)
        }
        try saveProject(project, folder: folder)
        return project
    }

    func deleteProject(folder: URL, projectID: UUID) throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try ProjectRegistryService.shared.remove(id: projectID)
    }

    static func projectFolderIsValid(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: ProjectPaths.projectJSON(in: folder).path)
    }
}
