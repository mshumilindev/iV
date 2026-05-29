import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { appState?.navigation = .library }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Manuscript") {
            importExportButtons(appState: appState, import: true)
            Divider()
            importExportButtons(appState: appState, import: false)
        }
        CommandMenu("Analysis") {
            Button("Run Selection Analysis") { appState?.runSelectionAnalysis() }
            Button("Run Current Paragraph Analysis") { appState?.runParagraphDiagnostics() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Run Current Scene Analysis") { appState?.runSceneAnalysis() }
            Button("Run Current Chapter Analysis") { appState?.runChapterAnalysis() }
            Button("Run Full Pipeline") { appState?.runFullPipeline() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Run Safe Auto Fix") { appState?.runSafeAutoFix() }
            Button("Suggest Chapter Split") { appState?.suggestChapterSplits() }
            Button("Build Context Packet") { appState?.buildContextPreview() }
            Divider()
            Button("Reload Edit Rules") { appState?.reloadEditRules() }
            Button("Check Ollama Connection") { Task { await appState?.refreshOllamaStatus() } }
        }
        CommandMenu("Edit") {
            Button("Undo") { EditorUndoController.undo(textView: appState?.findController.textView) }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { EditorUndoController.redo(textView: appState?.findController.textView) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Divider()
            Button("Save") { appState?.saveActiveDocumentNow() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Create Checkpoint…") { appState?.showManuscriptSnapshots = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Find…") {
                appState?.findController.isVisible = true
                if let tv = appState?.findController.textView {
                    appState?.findController.show(in: tv)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Editor") {
            Button("Toggle Focus Mode") { appState?.focusMode.toggle() }
            Menu("Reference Pane") {
                Button("None") { appState?.splitEditorReference = .none }
                Button("Import snapshot") { appState?.splitEditorReference = .importSnapshot }
                Button("Accepted baseline") { appState?.splitEditorReference = .acceptedBaseline }
                Button("Selected paragraph") { appState?.splitEditorReference = .selectedParagraph }
            }
            Menu("Performance Mode") {
                ForEach(PerformanceMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) { appState?.performanceMode = mode }
                }
            }
            Divider()
            Button("Semantic Search…") { appState?.workspaceInspectorTab = .search }
        }
        CommandMenu("Navigate") {
            Button("Project Overview") {
                guard let state = appState else { return }
                if let id = state.currentProject?.id {
                    state.navigation = .projectOverview(id)
                } else {
                    state.navigation = .library
                }
            }
            .keyboardShortcut("[", modifiers: .command)
            Button("Project Library") {
                appState?.navigation = .library
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Command Palette…") {
                appState?.showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }

    @ViewBuilder
    private func importExportButtons(appState: AppState?, import isImport: Bool) -> some View {
        let plainImport = PlainTextImportService()
        let rtfImport = RTFImportService()
        let docxImport = DOCXImportService()
        let plainExport = PlainTextExportService()
        let rtfExport = RTFExportService()
        let docxExport = DOCXExportService()

        if isImport {
            importButton(appState: appState, service: plainImport)
            importButton(appState: appState, service: rtfImport)
            importButton(appState: appState, service: docxImport)
        } else {
            exportButton(appState: appState, service: plainExport)
            exportButton(appState: appState, service: rtfExport)
            exportButton(appState: appState, service: docxExport)
        }
    }

    private func importButton(appState: AppState?, service: any DocumentImportService) -> some View {
        Button("Import \(service.menuLabel)…") {
            appState?.importManuscript(service: service)
        }
        .disabled(!service.isAvailable)
        .help(service.limitationSummary)
    }

    private func exportButton(appState: AppState?, service: any DocumentExportService) -> some View {
        Button("Export \(service.menuLabel)…") {
            appState?.exportManuscript(service: service)
        }
        .disabled(!service.isAvailable)
        .help(service.limitationSummary)
    }
}
