import Foundation

/// Abstraction over embedded office editor vs legacy NSTextView prototype.
@MainActor
protocol DocumentEditorEngine: AnyObject {
    var kind: DocumentEditorKind { get }
    var connectionState: DocumentEditorConnectionState { get }

    func refreshSelection()
    func currentSelection() -> DocumentEditorSelectionSnapshot

    func replaceSelection(with text: String) -> DocumentEditorMutationResult
    func insertAtCursor(_ text: String) -> DocumentEditorMutationResult
    func appendAfterSelection(_ text: String) -> DocumentEditorMutationResult

    /// Plain text for paragraph index / diagnostics (best-effort).
    func extractPlainTextForAnalysis() -> String?
}
