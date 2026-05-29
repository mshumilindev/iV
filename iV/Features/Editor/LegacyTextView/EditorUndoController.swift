import AppKit

/// Forwards undo/redo to the active manuscript `NSTextView` without clearing its stack on autosave.
@MainActor
enum EditorUndoController {
    static func undo(textView: NSTextView?) {
        guard let textView, let manager = textView.undoManager, manager.canUndo else { return }
        textView.window?.makeFirstResponder(textView)
        manager.undo()
    }

    static func redo(textView: NSTextView?) {
        guard let textView, let manager = textView.undoManager, manager.canRedo else { return }
        textView.window?.makeFirstResponder(textView)
        manager.redo()
    }

    static func canUndo(textView: NSTextView?) -> Bool {
        textView?.undoManager?.canUndo ?? false
    }

    static func canRedo(textView: NSTextView?) -> Bool {
        textView?.undoManager?.canRedo ?? false
    }
}
