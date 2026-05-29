import Foundation

// MARK: - Chat target (selection-aware)

enum AiChatTarget: Sendable, Equatable {
    case selection(
        documentId: UUID,
        selectedText: String,
        selectionPreview: String,
        selectionRange: UnknownEditorRange?
    )
    case cursor(
        documentId: UUID,
        cursorContextBefore: String?,
        cursorContextAfter: String?
    )
    case document(
        documentId: UUID,
        documentTitle: String?,
        documentExcerpt: String?
    )
    case project(projectId: UUID)

    var documentId: UUID? {
        switch self {
        case .selection(let id, _, _, _),
             .cursor(let id, _, _),
             .document(let id, _, _):
            return id
        case .project:
            return nil
        }
    }
}

/// Opaque until office editor range API is validated at runtime.
struct UnknownEditorRange: Sendable, Equatable {
    let payload: [String: String]
}

enum AiChatInstructionMode: String, Sendable, Codable, CaseIterable {
    case generate
    case rewrite
    case analyze
    case `continue`
    case summarize
    case critique
    case custom

    var displayName: String {
        switch self {
        case .generate: "Generate"
        case .rewrite: "Rewrite"
        case .analyze: "Analyze"
        case .continue: "Continue"
        case .summarize: "Summarize"
        case .critique: "Critique"
        case .custom: "Custom"
        }
    }
}

struct AiChatRequest: Sendable {
    let projectId: UUID
    let documentId: UUID?
    let userMessage: String
    let target: AiChatTarget
    let rulesContext: String?
    let documentContext: String?
    let selectedText: String?
    let instructionMode: AiChatInstructionMode
}

// MARK: - UI messages

enum AiChatRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

struct AiChatMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: AiChatRole
    let text: String
    let createdAt: Date
    /// When assistant message — available apply actions.
    let proposedActions: [AiChatApplyAction]

    init(
        id: UUID = UUID(),
        role: AiChatRole,
        text: String,
        createdAt: Date = Date(),
        proposedActions: [AiChatApplyAction] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.proposedActions = proposedActions
    }
}

enum AiChatApplyAction: String, Sendable, CaseIterable, Identifiable {
    case replaceSelection
    case insertAtCursor
    case appendAfterSelection
    case copyOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replaceSelection: "Replace selection"
        case .insertAtCursor: "Insert at cursor"
        case .appendAfterSelection: "Append after selection"
        case .copyOnly: "Copy"
        }
    }
}
