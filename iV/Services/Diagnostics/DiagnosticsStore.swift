import Foundation

@MainActor
final class DiagnosticsStore {
    func load(documentID: UUID, folder: URL) throws -> [Diagnostic] {
        let url = ProjectPaths.diagnosticsURL(folder: folder, documentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try AtomicFileWriter.read([Diagnostic].self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    func save(_ diagnostics: [Diagnostic], documentID: UUID, folder: URL) throws {
        try AtomicFileWriter.write(diagnostics, to: ProjectPaths.diagnosticsURL(folder: folder, documentID: documentID))
    }

    func loadProposals(documentID: UUID, folder: URL) throws -> [ChangeProposal] {
        let url = ProjectPaths.proposalsURL(folder: folder, documentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try AtomicFileWriter.read([ChangeProposal].self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    func saveProposals(_ proposals: [ChangeProposal], documentID: UUID, folder: URL) throws {
        try AtomicFileWriter.write(proposals, to: ProjectPaths.proposalsURL(folder: folder, documentID: documentID))
    }

    func loadAnalysisRuns(folder: URL) throws -> [AnalysisRun] {
        let url = ProjectPaths.analysisRunsURL(folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try AtomicFileWriter.read([AnalysisRun].self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    func saveAnalysisRuns(_ runs: [AnalysisRun], folder: URL) throws {
        try AtomicFileWriter.write(runs, to: ProjectPaths.analysisRunsURL(folder: folder))
    }
}

@MainActor
final class CanonSuggestionStore {
    func load(folder: URL) throws -> [CanonUpdateSuggestion] {
        let url = ProjectPaths.canonSuggestionsURL(folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try AtomicFileWriter.read([CanonUpdateSuggestion].self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    func save(_ suggestions: [CanonUpdateSuggestion], folder: URL) throws {
        try AtomicFileWriter.write(suggestions, to: ProjectPaths.canonSuggestionsURL(folder: folder))
    }
}

@MainActor
final class CanonStore {
    func load(folder: URL) throws -> [CanonEntity] {
        let url = ProjectPaths.canonURL(folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try AtomicFileWriter.read([CanonEntity].self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    func save(_ entities: [CanonEntity], folder: URL) throws {
        try AtomicFileWriter.write(entities, to: ProjectPaths.canonURL(folder: folder))
    }

    func loadMemory(folder: URL) throws -> [NarrativeMemory] {
        let url = ProjectPaths.narrativeMemoryURL(folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try AtomicFileWriter.read([NarrativeMemory].self, from: url)
        } catch {
            throw PersistenceError.storeReadFailed(resource: url.lastPathComponent, underlying: error)
        }
    }

    func saveMemory(_ memory: [NarrativeMemory], folder: URL) throws {
        try AtomicFileWriter.write(memory, to: ProjectPaths.narrativeMemoryURL(folder: folder))
    }
}
