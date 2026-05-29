import Foundation

/// Schema versions for on-disk JSON. Bump when making breaking encoding changes.
enum PersistenceSchema {
    static let projectRegistry = 1
    static let project = 1
    static let document = 1
}

struct ProjectRegistryFile: Codable, Sendable {
    var schemaVersion: Int
    var entries: [ProjectRegistryEntry]

    init(schemaVersion: Int = PersistenceSchema.projectRegistry, entries: [ProjectRegistryEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

enum RegistryPersistence {
  /// Supports legacy bare `[ProjectRegistryEntry]` and versioned `{ schemaVersion, entries }`.
    static func decodeEntries(from data: Data) throws -> [ProjectRegistryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(ProjectRegistryFile.self, from: data) {
            return file.entries
        }
        return try decoder.decode([ProjectRegistryEntry].self, from: data)
    }

    static func encodeEntries(_ entries: [ProjectRegistryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = ProjectRegistryFile(entries: entries)
        return try encoder.encode(file)
    }
}
