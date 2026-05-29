import SwiftUI

/// Primary manuscript surface — embedded office shell or legacy NSTextView fallback.
struct EmbeddedDocumentEditorView: View {
    @Environment(AppState.self) private var appState
    let documentTitle: String

    var body: some View {
        switch appState.documentEditorBridge.editorKind {
        case .embeddedOffice:
            EmbeddedOfficeEditorShellView(
                coordinator: appState.embeddedOfficeCoordinator,
                onOpenSettings: { appState.showSettings = true },
                onSwitchToLegacy: { appState.switchDocumentEditorToLegacyFallback() }
            )
            .onAppear { syncCoordinator() }
            .onChange(of: appState.activeDocument?.id) { _, _ in syncCoordinator() }
            .onChange(of: appState.documentEditorBridge.documentServerURL) { _, _ in syncCoordinator() }
            .onChange(of: appState.documentEditorBridge.editorKind) { _, _ in syncCoordinator() }
            .onChange(of: appState.embeddedOfficeCoordinator.lifecycle) { _, _ in
                appState.documentEditorBridge.connectionState = appState.embeddedOfficeCoordinator.connectionState
            }
            .onChange(of: appState.embeddedOfficeCoordinator.hostConnectionState) { _, _ in
                appState.documentEditorBridge.connectionState = appState.embeddedOfficeCoordinator.connectionState
            }
        case .legacyPrototype:
            legacyEditor
        }
    }

    private func syncCoordinator() {
        appState.syncEmbeddedOfficeEditor()
    }

    private var legacyEditor: some View {
        VStack(spacing: 0) {
            LegacyEditorStatusStrip()
                .ivForestElevatedBar()
            RichTextEditor(
                text: Binding(
                    get: { appState.activeDocument?.plainText ?? "" },
                    set: { appState.onEditorTextChange($0) }
                ),
                contentEpoch: appState.editorContentEpoch,
                diagnostics: appState.diagnostics,
                focusMode: appState.focusMode,
                findController: appState.findController,
                onTextViewReady: { appState.findController.textView = $0 },
                onSelectionChange: { location, length in
                    appState.selectionLocation = location
                    appState.selectionLength = length
                    appState.documentEditorBridge.selection = DocumentEditorSelectionSnapshot(
                        selectedText: appState.selectedTextInActiveDocument,
                        selectionPreview: String(appState.selectedTextInActiveDocument.prefix(120)),
                        location: location,
                        length: length,
                        editorRange: nil
                    )
                    if let index = appState.documentIndex {
                        appState.selectedParagraphID = ParagraphIndexer().paragraph(at: location, index: index)?.id
                    }
                },
                onTextChange: { appState.onEditorTextChange($0) },
                scrollToRange: appState.scrollToRange
            )
            .accessibilityIdentifier("workspace.manuscript.active")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IVColor.forestBlack)
    }
}

private struct LegacyEditorStatusStrip: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: IVLayout.statusBarItemSpacing) {
            if let doc = appState.activeDocument {
                IVStatusItem(text: doc.title, emphasis: true)
                IVStatusSeparator()
            }
            switch appState.documentSaveState {
            case .saved: IVStatusItem(text: "Saved")
            case .unsaved: IVStatusItem(text: "Unsaved", warning: true)
            case .saving: IVStatusItem(text: "Saving…")
            case .saveError: IVStatusItem(text: "Save error", warning: true)
            }
            IVStatusSeparator()
            IVStatusItem(text: DocumentEditorKind.legacyPrototype.statusLabel, warning: true)
            IVStatusSeparator()
            IVStatusItem(text: "Not production editor", warning: true)
            if appState.openDiagnosticCount > 0 {
                IVStatusSeparator()
                IVStatusItem(text: "\(appState.openDiagnosticCount) issues", warning: true)
            }
            Spacer()
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, 6)
    }
}
