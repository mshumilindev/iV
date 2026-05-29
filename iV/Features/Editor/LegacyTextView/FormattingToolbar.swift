import SwiftUI

struct FormattingToolbar: View {
    var textView: NSTextView?

    var body: some View {
        HStack(spacing: 4) {
            formatButton("bold", systemImage: "bold") {
                if let tv = textView { EditorFormatting.toggleBold(in: tv) }
            }
            formatButton("italic", systemImage: "italic") {
                if let tv = textView { EditorFormatting.toggleItalic(in: tv) }
            }
            formatButton("underline", systemImage: "underline") {
                if let tv = textView { EditorFormatting.toggleUnderline(in: tv) }
            }
            Divider().frame(height: 16)
            formatButton("H1", systemImage: "textformat.size.larger") {
                if let tv = textView { EditorFormatting.applyHeading(1, in: tv) }
            }
            formatButton("H2", systemImage: "textformat.size") {
                if let tv = textView { EditorFormatting.applyHeading(2, in: tv) }
            }
            Divider().frame(height: 16)
            Button {
                EditorUndoController.undo(textView: textView)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.ivIcon)
            .disabled(!EditorUndoController.canUndo(textView: textView))
            .help("Undo")
            Button {
                EditorUndoController.redo(textView: textView)
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.ivIcon)
            .disabled(!EditorUndoController.canRedo(textView: textView))
            .help("Redo")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .ivForestElevatedBar()
        .foregroundStyle(IVColor.chromePrimary)
    }

    private func formatButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.ivIcon)
        .help(title)
    }
}
