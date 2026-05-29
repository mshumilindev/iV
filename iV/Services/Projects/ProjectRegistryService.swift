import Foundation

@MainActor
final class ProjectRegistryService {
    static let shared = ProjectRegistryService()

    private(set) var entries: [ProjectRegistryEntry] = []

    /// Test-only: seed entries before exercising save/load.
    func replaceEntriesForTesting(_ entries: [ProjectRegistryEntry]) {
        self.entries = entries
    }
    private(set) var lastLoadError: Error?
    private(set) var lastSaveError: Error?

    var isCorrupt: Bool { lastLoadError != nil }

    private init() {}

    func load() throws {
        try load(from: ProjectPaths.globalRegistryURL())
    }

    func load(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries = []
            lastLoadError = nil
            return
        }
        do {
            let data = try Data(contentsOf: url)
            entries = try RegistryPersistence.decodeEntries(from: data)
            lastLoadError = nil
        } catch {
            lastLoadError = error
            throw PersistenceError.registryCorrupt(path: url.path, underlying: error)
        }
    }

    func save() throws {
        try save(to: ProjectPaths.globalRegistryURL())
    }

    func save(to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try RegistryPersistence.encodeEntries(entries)
            try AtomicFileWriter.write(data: data, to: url)
            lastSaveError = nil
        } catch {
            lastSaveError = error
            throw PersistenceError.registrySaveFailed(path: url.path, underlying: error)
        }
    }

    func upsert(_ entry: ProjectRegistryEntry) throws {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try save()
    }

    func remove(id: UUID) throws {
        entries.removeAll { $0.id == id }
        try save()
    }

    func entry(for id: UUID) -> ProjectRegistryEntry? {
        entries.first { $0.id == id }
    }

    /// Removes library entries whose project folder or project.json no longer exists (e.g. after unit tests).
    @discardableResult
    func pruneMissingProjectFolders() throws -> Int {
        let before = entries.count
        entries.removeAll { !ProjectStore.projectFolderIsValid($0.folderURL) }
        let removed = before - entries.count
        if removed > 0 { try save() }
        return removed
    }
}
