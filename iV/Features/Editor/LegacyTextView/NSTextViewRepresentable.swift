import AppKit
import SwiftUI

// MARK: - Legacy prototype editor (non-final)
// `RichTextEditor` / `NSTextView` is NOT the product manuscript surface.
// See docs/DOCUMENT_EDITOR_ARCHITECTURE.md — use `EmbeddedDocumentEditorView` + ONLYOFFICE.

struct NSTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    /// Bumps when manuscript is loaded/imported/restored — avoids replacing `string` during typing (preserves undo).
    var contentEpoch: Int
    var diagnostics: [Diagnostic]
    var focusMode: Bool
    var findController: FindReplaceController?
    var onTextViewReady: ((NSTextView) -> Void)?
    var onSelectionChange: ((Int, Int) -> Void)?
    var onTextChange: ((String) -> Void)?
    var scrollToRange: NSRange?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = IVColor.documentSurfaceNS

        let textView = context.coordinator.textView
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.font = IVTheme.manuscriptFont
        textView.textColor = IVColor.documentTextNS
        textView.insertionPointColor = IVColor.documentTextNS
        textView.backgroundColor = .clear
        textView.defaultParagraphStyle = IVTheme.manuscriptParagraphStyle
        textView.typingAttributes = IVTheme.manuscriptDefaultTypingAttributes
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.applyManuscriptTypography()

        scrollView.documentView = textView
        scrollView.setAccessibilityIdentifier("workspace.manuscript")
        textView.setAccessibilityIdentifier("workspace.manuscript.editor")
        findController?.textView = textView
        onTextViewReady?(textView)
        context.coordinator.applyDiagnosticHighlights(diagnostics)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = context.coordinator.textView
        findController?.textView = textView
        if context.coordinator.lastAppliedEpoch != contentEpoch {
            context.coordinator.lastAppliedEpoch = contentEpoch
            if textView.string != text {
                context.coordinator.isUpdating = true
                let selected = textView.selectedRange()
                textView.string = text
                textView.setSelectedRange(selected)
                textView.undoManager?.removeAllActions()
                context.coordinator.isUpdating = false
                context.coordinator.applyManuscriptTypography()
            }
        }
        context.coordinator.applyDiagnosticHighlights(diagnostics)
        textView.textContainer?.widthTracksTextView = focusMode
        scrollView.drawsBackground = true
        scrollView.backgroundColor = IVColor.documentSurfaceNS
        if let scrollToRange {
            textView.scrollRangeToVisible(scrollToRange)
            textView.showFindIndicator(for: scrollToRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: NSTextViewRepresentable
        let textView = NSTextView()
        var isUpdating = false
        var lastAppliedEpoch: Int = -1

        init(_ parent: NSTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            parent.text = textView.string
            parent.onTextChange?(textView.string)
            parent.findController?.updateMatchCount()
            applyManuscriptTypography()
        }

        /// Keeps body text on manuscript stack (New York 18pt) without clobbering diagnostic highlight attrs.
        func applyManuscriptTypography() {
            guard let storage = textView.textStorage, storage.length > 0 else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.addAttributes(
                [
                    .font: IVTheme.manuscriptFont,
                    .foregroundColor: IVColor.documentTextNS,
                    .paragraphStyle: IVTheme.manuscriptParagraphStyle
                ],
                range: fullRange
            )
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            let range = textView.selectedRange()
            parent.onSelectionChange?(range.location, range.length)
        }

        func applyDiagnosticHighlights(_ diagnostics: [Diagnostic]) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.underlineStyle, range: fullRange)
            storage.removeAttribute(.underlineColor, range: fullRange)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            for diagnostic in diagnostics where !diagnostic.isStale && diagnostic.status == .open {
                guard let start = diagnostic.startOffset, let end = diagnostic.endOffset else { continue }
                let range = NSRange(location: start, length: max(0, end - start))
                guard NSMaxRange(range) <= storage.length else { continue }
                switch diagnostic.severity {
                case .info:
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    storage.addAttribute(.underlineColor, value: IVColor.diagnosticInfoNS, range: range)
                case .warning:
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: range)
                    storage.addAttribute(.underlineColor, value: IVColor.diagnosticWarningNS, range: range)
                case .error:
                    storage.addAttribute(.backgroundColor, value: IVColor.diagnosticErrorNS.withAlphaComponent(0.18), range: range)
                case .blocking:
                    storage.addAttribute(.backgroundColor, value: IVColor.diagnosticBlockingNS.withAlphaComponent(0.28), range: range)
                }
            }
        }
    }
}

struct RichTextEditor: View {
    @Binding var text: String
    var contentEpoch: Int = 0
    var diagnostics: [Diagnostic]
    var focusMode: Bool
    var findController: FindReplaceController?
    var onTextViewReady: ((NSTextView) -> Void)?
    var onSelectionChange: ((Int, Int) -> Void)?
    var onTextChange: ((String) -> Void)?
    var scrollToRange: NSRange?

    var body: some View {
        IVManuscriptSurface(maxContentWidth: .infinity) {
            NSTextViewRepresentable(
                text: $text,
                contentEpoch: contentEpoch,
                diagnostics: diagnostics,
                focusMode: focusMode,
                findController: findController,
                onTextViewReady: onTextViewReady,
                onSelectionChange: onSelectionChange,
                onTextChange: onTextChange,
                scrollToRange: scrollToRange
            )
        }
    }
}
