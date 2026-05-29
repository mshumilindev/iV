import Foundation
import Observation

/// Observable bridge between workspace UI, AI chat, and the active document editor engine.
@MainActor
@Observable
final class DocumentEditorBridge {
    var editorKind: DocumentEditorKind = .embeddedOffice
    var connectionState: DocumentEditorConnectionState = .unavailable(
        "Document Server not configured. Set URL in Settings."
    )
    var selection: DocumentEditorSelectionSnapshot = .empty
    var documentServerURL: String = DocumentEditorSettings.defaultServerURL

    private var legacyPlainTextProvider: (() -> String?)?
    private var legacySelectionProvider: (() -> (text: String, location: Int, length: Int)?)?

    func configureLegacyProviders(
        plainText: @escaping () -> String?,
        selection: @escaping () -> (text: String, location: Int, length: Int)?
    ) {
        legacyPlainTextProvider = plainText
        legacySelectionProvider = selection
    }

    func refreshSelection() {
        switch editorKind {
        case .legacyPrototype:
            if let sel = legacySelectionProvider?() {
                let preview = String(sel.text.prefix(120))
                selection = DocumentEditorSelectionSnapshot(
                    selectedText: sel.text,
                    selectionPreview: preview,
                    location: sel.location,
                    length: sel.length,
                    editorRange: nil
                )
            } else {
                selection = .empty
            }
        case .embeddedOffice:
            // Updated by ONLYOFFICEEditorHost via JS callbacks when wired.
            break
        }
    }

    func buildAiChatTarget(documentId: UUID, projectId: UUID, plainText: String) -> AiChatTarget {
        refreshSelection()
        if selection.hasSelection {
            return .selection(
                documentId: documentId,
                selectedText: selection.selectedText,
                selectionPreview: selection.selectionPreview,
                selectionRange: selection.editorRange
            )
        }
        let loc = selection.location
        if loc > 0, loc <= plainText.count {
            let idx = plainText.index(plainText.startIndex, offsetBy: min(loc, plainText.count))
            let before = String(plainText[..<idx].suffix(400))
            let after = String(plainText[idx...].prefix(400))
            return .cursor(
                documentId: documentId,
                cursorContextBefore: before.isEmpty ? nil : before,
                cursorContextAfter: after.isEmpty ? nil : after
            )
        }
        let excerpt = String(plainText.prefix(2000))
        return .document(
            documentId: documentId,
            documentTitle: nil,
            documentExcerpt: excerpt.isEmpty ? nil : excerpt
        )
    }

    func applyMutation(_ action: AiChatApplyAction, text: String, mutateLegacyPlainText: (String) -> Void) -> DocumentEditorMutationResult {
        switch editorKind {
        case .legacyPrototype:
            return applyLegacy(action: action, text: text, mutatePlainText: mutateLegacyPlainText)
        case .embeddedOffice:
            switch action {
            case .copyOnly:
                return .applied
            default:
                return .unavailable("Connect ONLYOFFICE Document Server and complete the JS bridge (Phase 3).")
            }
        }
    }

    private func applyLegacy(
        action: AiChatApplyAction,
        text: String,
        mutatePlainText: (String) -> Void
    ) -> DocumentEditorMutationResult {
        guard let full = legacyPlainTextProvider?() else {
            return .unavailable("Legacy editor not active.")
        }
        refreshSelection()
        switch action {
        case .copyOnly:
            return .applied
        case .replaceSelection:
            guard selection.hasSelection else {
                return .failed("No text selected.")
            }
            var updated = full
            let start = selection.location
            let end = min(start + selection.length, updated.count)
            let startIdx = updated.index(updated.startIndex, offsetBy: start)
            let endIdx = updated.index(updated.startIndex, offsetBy: end)
            updated.replaceSubrange(startIdx..<endIdx, with: text)
            mutatePlainText(updated)
            return .applied
        case .insertAtCursor:
            let loc = min(selection.location, full.count)
            var updated = full
            let idx = updated.index(updated.startIndex, offsetBy: loc)
            updated.insert(contentsOf: text, at: idx)
            mutatePlainText(updated)
            return .applied
        case .appendAfterSelection:
            let loc = min(selection.location + selection.length, full.count)
            var updated = full
            let idx = updated.index(updated.startIndex, offsetBy: loc)
            updated.insert(contentsOf: text, at: idx)
            mutatePlainText(updated)
            return .applied
        }
    }
}

enum DocumentEditorSettings {
    static let defaultServerURL = "http://127.0.0.1:8080"
    static let serverURLKey = "iv.documentServerURL"
    static let editorKindKey = "iv.documentEditorKind"
    static let editorKindUserSelectedKey = "iv.documentEditorKindUserSelected"
    static let dockerCLIPathKey = "iv.dockerCLIPath"

    /// In-memory override — never written to UserDefaults. Used for UITest legacy automation.
    private(set) static var inMemoryEditorKindOverride: DocumentEditorKind?

    static func setInMemoryEditorKindOverride(_ kind: DocumentEditorKind?) {
        inMemoryEditorKindOverride = kind
    }

    static func loadServerURL() -> String {
        UserDefaults.standard.string(forKey: serverURLKey) ?? defaultServerURL
    }

    static func saveServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: serverURLKey)
    }

    static func loadDockerCLIPath() -> String? {
        UserDefaults.standard.string(forKey: dockerCLIPathKey)
    }

    static func saveDockerCLIPath(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: dockerCLIPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: dockerCLIPathKey)
        }
    }

    static func hasUserSelectedEditorKind() -> Bool {
        UserDefaults.standard.bool(forKey: editorKindUserSelectedKey)
    }

    /// Resets legacy preference written by older UITest/bootstrap flows when the user never chose it.
    static func clearTestPollutedLegacyDefaultIfNeeded() {
        guard let raw = UserDefaults.standard.string(forKey: editorKindKey),
              raw == DocumentEditorKind.legacyPrototype.rawValue,
              !hasUserSelectedEditorKind()
        else { return }
        UserDefaults.standard.set(DocumentEditorKind.embeddedOffice.rawValue, forKey: editorKindKey)
    }

    static func loadEditorKind() -> DocumentEditorKind {
        clearTestPollutedLegacyDefaultIfNeeded()
        guard let raw = UserDefaults.standard.string(forKey: editorKindKey),
              let kind = DocumentEditorKind(rawValue: raw) else {
            return .embeddedOffice
        }
        return kind
    }

    /// Effective engine for the running app (honours in-memory UITest override when set).
    static func resolvedEditorKind() -> DocumentEditorKind {
        inMemoryEditorKindOverride ?? loadEditorKind()
    }

    static func saveEditorKind(_ kind: DocumentEditorKind, userSelected: Bool = false) {
        UserDefaults.standard.set(kind.rawValue, forKey: editorKindKey)
        if userSelected {
            UserDefaults.standard.set(true, forKey: editorKindUserSelectedKey)
        }
        if inMemoryEditorKindOverride != nil, kind != inMemoryEditorKindOverride {
            inMemoryEditorKindOverride = nil
        }
    }
}
