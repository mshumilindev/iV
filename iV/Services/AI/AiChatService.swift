import Foundation

/// Builds prompts and calls local Ollama for the AI Assistant panel.
struct AiChatService: Sendable {
    func buildPrompt(request: AiChatRequest) -> String {
        var parts: [String] = []
        parts.append("You are a writing assistant inside a fiction manuscript workstation.")
        parts.append("Do not claim to have applied changes to the document. Output only the requested prose or analysis.")
        parts.append("Instruction mode: \(request.instructionMode.rawValue)")
        parts.append("User message: \(request.userMessage)")

        switch request.target {
        case .selection(_, let selected, let preview, _):
            parts.append("TARGET: selected text (primary focus).")
            parts.append("Selection preview: \(preview)")
            parts.append("Full selection:\n\(selected)")
        case .cursor(_, let before, let after):
            parts.append("TARGET: cursor position (no selection).")
            if let before { parts.append("Text before cursor:\n\(before)") }
            if let after { parts.append("Text after cursor:\n\(after)") }
        case .document(_, let title, let excerpt):
            parts.append("TARGET: document scope.")
            if let title { parts.append("Title: \(title)") }
            if let excerpt { parts.append("Excerpt:\n\(excerpt)") }
        case .project:
            parts.append("TARGET: project scope.")
        }

        if let rules = request.rulesContext, !rules.isEmpty {
            parts.append("Active editorial rules:\n\(rules)")
        }
        if let doc = request.documentContext, !doc.isEmpty {
            parts.append("Additional document context:\n\(doc)")
        }
        return parts.joined(separator: "\n\n")
    }

    func suggestedActions(for mode: AiChatInstructionMode, hasSelection: Bool) -> [AiChatApplyAction] {
        switch mode {
        case .analyze, .critique, .summarize:
            return [.copyOnly]
        case .generate, .continue:
            return hasSelection
                ? [.replaceSelection, .appendAfterSelection, .insertAtCursor, .copyOnly]
                : [.insertAtCursor, .copyOnly]
        case .rewrite, .custom:
            return hasSelection
                ? [.replaceSelection, .appendAfterSelection, .copyOnly]
                : [.insertAtCursor, .copyOnly]
        }
    }
}
