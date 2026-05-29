import Foundation

enum CanonSuggestionStatus: String, Codable, Sendable {
    case pending, accepted, rejected
}

struct CanonUpdateSuggestion: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var entityType: CanonEntityType
    var name: String
    var fact: String
    var reason: String
    var status: CanonSuggestionStatus
    var source: DiagnosticSource
    var createdAt: Date

    init(from llm: LLMCanonUpdateSuggestion, projectID: UUID, source: DiagnosticSource = .llm) {
        self.id = UUID()
        self.projectID = projectID
        self.entityType = CanonEntityType(rawValue: llm.entityType) ?? .term
        self.name = llm.name
        self.fact = llm.fact
        self.reason = llm.reason
        self.status = .pending
        self.source = source
        self.createdAt = Date()
    }
}
