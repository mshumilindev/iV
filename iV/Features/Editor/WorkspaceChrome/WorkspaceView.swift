import SwiftUI

struct WorkspaceView: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarSection: WorkspaceSidebarSection = .documents
    @State private var inspectorSection: WorkspaceInspectorSection = .diagnostics
    @State private var showInspectorPanel = false
    @State private var showSceneExpansion = false
    @State private var showRulesBrowser = false
    @State private var sceneSkeleton = ""
    @State private var editingSceneID: UUID?
    @State private var sceneFunctionDraft = ""
    @State private var pendingDeleteDocument: Document?
    @State private var pendingImportReplace: DocumentImportService?

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            HSplitView {
                sidebar
                    .frame(
                        minWidth: WorkspaceLayout.sidebarMinWidth,
                        idealWidth: WorkspaceLayout.sidebarIdealWidth,
                        maxWidth: WorkspaceLayout.sidebarMaxWidth
                    )
                    .layoutPriority(-1)

                HSplitView {
                    editorArea
                        .frame(minWidth: WorkspaceLayout.editorMinWidth)
                        .layoutPriority(1)

                    if showInspectorPanel {
                        inspector
                            .frame(
                                minWidth: WorkspaceLayout.inspectorMinWidth,
                                idealWidth: WorkspaceLayout.inspectorIdealWidth,
                                maxWidth: WorkspaceLayout.inspectorMaxWidth
                            )
                            .layoutPriority(-1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("nav.workspace")
        .accessibilityElement(children: .contain)
        .toolbar { workspaceToolbar }
        .ivWindowToolbar()
        .background(IVColor.forestBlack)
        .ivChromeFooter { StatusBarView() }
        .sheet(isPresented: Bindable(appState).showSettings) {
            SettingsView().ivSheetChrome()
        }
        .sheet(isPresented: Bindable(appState).showManuscriptSnapshots) {
            ManuscriptSnapshotsView().ivSheetChrome()
        }
        .sheet(isPresented: Bindable(appState).showCommandPalette) {
            CommandPaletteView(isPresented: Bindable(appState).showCommandPalette)
                .ivSheetChrome()
        }
        .sheet(isPresented: $showRulesBrowser) {
            EditRulesBrowserView().ivSheetChrome()
        }
        .sheet(isPresented: $showSceneExpansion) {
            SceneExpansionSheet(
                skeleton: $sceneSkeleton,
                isRunning: appState.isSceneExpansionRunning
            ) { outcome in
                appState.createSceneExpansionProposal(skeleton: sceneSkeleton, outcome: outcome)
            }
            .ivSheetChrome()
        }
        .sheet(isPresented: Binding(
            get: { editingSceneID != nil },
            set: { if !$0 { editingSceneID = nil } }
        )) {
            if let sceneID = editingSceneID {
                sceneFunctionSheet(sceneID: sceneID)
            }
        }
        .onAppear {
            showInspectorPanel = appState.openDiagnosticCount > 0
            inspectorSection = .diagnostics
        }
        .onChange(of: appState.workspaceSidebarTab) { _, tab in
            if let tab {
                sidebarSection = tab
                appState.workspaceSidebarTab = nil
            }
        }
        .onChange(of: appState.workspaceInspectorTab) { _, tab in
            if let tab {
                inspectorSection = tab
                showInspectorPanel = true
                appState.workspaceInspectorTab = nil
            }
        }
        .onChange(of: appState.openDiagnosticCount) { old, new in
            if old == 0, new > 0 {
                showInspectorPanel = true
                inspectorSection = .diagnostics
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeleteDocument?.title ?? "")”?",
            isPresented: Binding(
                get: { pendingDeleteDocument != nil },
                set: { if !$0 { pendingDeleteDocument = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Document", role: .destructive) {
                if let doc = pendingDeleteDocument { appState.deleteDocument(doc) }
                pendingDeleteDocument = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteDocument = nil }
        } message: {
            Text("Removes the manuscript file and its diagnostics from this project.")
        }
        .confirmationDialog(
            "Replace current manuscript?",
            isPresented: Binding(
                get: { pendingImportReplace != nil },
                set: { if !$0 { pendingImportReplace = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                if let service = pendingImportReplace {
                    appState.importManuscript(service: service, replaceActive: true)
                }
                pendingImportReplace = nil
            }
            Button("Cancel", role: .cancel) { pendingImportReplace = nil }
        } message: {
            Text("Imported text will overwrite the active document. This cannot be undone except via undo in the editor.")
        }
    }

    private func sceneFunctionSheet(sceneID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IVSheetHeaderBar(title: "Scene function", onDismiss: { editingSceneID = nil })
            TextField("What this scene must accomplish", text: $sceneFunctionDraft, axis: .vertical)
            HStack {
                Spacer()
                Button("Cancel") { editingSceneID = nil }
                    .buttonStyle(.ivGhost)
                Button("Save") {
                    appState.updateSceneFunction(sceneID: sceneID, function: sceneFunctionDraft)
                    editingSceneID = nil
                }
                .buttonStyle(.ivPrimary)
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 420)
        .ivSheetChrome()
        .onAppear {
            sceneFunctionDraft = appState.structure.scenes.first { $0.id == sceneID }?.function ?? ""
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceSidebarNav(selection: $sidebarSection)
            Group {
                switch sidebarSection {
                case .documents:
                    documentsSidebar
                case .structure:
                    WorkspaceStructureSidebar()
                case .canon:
                    CanonVaultView()
                case .rules:
                    RuleFilesView()
                case .memory:
                    NarrativeMemoryView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .ivForestPanel()
        .clipped()
    }

    private var documentsSidebar: some View {
        Group {
            if appState.documents.isEmpty {
                IVEmptyWorkspaceState(
                    title: "No manuscripts",
                    message: "Create or import a manuscript from Overview, or use Manuscript → Import in the menu.",
                    actionTitle: "Overview",
                    action: {
                        if let id = appState.currentProject?.id { appState.navigation = .projectOverview(id) }
                    }
                )
                .padding(IVLayout.stackS)
            } else {
                List {
                    ForEach(appState.documents) { doc in
                        Button(doc.title) { appState.loadDocument(doc) }
                            .buttonStyle(.plain)
                            .ivFireflyRow(selected: appState.activeDocument?.id == doc.id)
                            .fontWeight(appState.activeDocument?.id == doc.id ? .semibold : .regular)
                            .contextMenu {
                                Button("Delete…", role: .destructive) { pendingDeleteDocument = doc }
                            }
                    }
                }
                .ivInspectorList()
            }
        }
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            WorkspaceEditorChrome(
                showSceneExpansion: $showSceneExpansion,
                openIssueCount: appState.openDiagnosticCount,
                onToggleInspector: toggleInspector,
                inspectorVisible: showInspectorPanel,
                onShowAssistant: { showInspector(section: .assistant) },
                onEditRules: {
                    appState.reloadProjectEditRules()
                    showRulesBrowser = true
                }
            )
            .ivForestElevatedBar()
            .overlay(alignment: .bottom) {
                IVEditorChromeFocusEdge(active: appState.activeDocument != nil)
            }

            if appState.findController.isVisible {
                FindReplaceBar(controller: appState.findController)
            }

            if appState.documentEditorBridge.editorKind == .legacyPrototype {
                FormattingToolbar(textView: appState.findController.textView)
            }

            if appState.activeDocument != nil {
                if appState.revisionReviewActive, let proposal = appState.selectedProposal {
                    HSplitView {
                        EmbeddedDocumentEditorView(documentTitle: appState.activeDocument?.title ?? "Manuscript")
                            .frame(minWidth: 280)
                        RevisionSplitView(proposal: proposal, displayMode: appState.diffDisplayMode)
                            .frame(minWidth: 280)
                    }
                } else if appState.splitEditorReference != .none, let refText = appState.referencePaneText, !refText.isEmpty {
                    HSplitView {
                        EmbeddedDocumentEditorView(documentTitle: appState.activeDocument?.title ?? "Manuscript")
                            .frame(minWidth: 320)
                        ReferencePaneView(
                            title: appState.referencePaneTitle,
                            text: refText,
                            onClose: { appState.splitEditorReference = .none }
                        )
                        .frame(minWidth: 240)
                    }
                } else {
                    EmbeddedDocumentEditorView(documentTitle: appState.activeDocument?.title ?? "Manuscript")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                IVEmptyWorkspaceState(
                    title: "No manuscript open",
                    message: "Choose a document in the sidebar, or create or import one from Overview.",
                    actionTitle: "Overview",
                    action: {
                        if let id = appState.currentProject?.id { appState.navigation = .projectOverview(id) }
                    }
                )
                .accessibilityIdentifier("workspace.manuscript.empty")
                .background(IVColor.documentSurface)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IVColor.forestBlack)
        .clipped()
        .accessibilityIdentifier("workspace.editor")
    }

    private func toggleInspector() {
        if showInspectorPanel {
            showInspectorPanel = false
        } else {
            if inspectorSection == .diagnostics, appState.openDiagnosticCount == 0 {
                inspectorSection = .assistant
            }
            showInspectorPanel = true
        }
    }

    private func showInspector(section: WorkspaceInspectorSection) {
        inspectorSection = section
        showInspectorPanel = true
    }

    @ViewBuilder
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceInspectorNav(
                selection: $inspectorSection,
                openIssueCount: appState.openDiagnosticCount,
                onHideInspector: { showInspectorPanel = false }
            )
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ivForestPanel()
        .clipped()
        .accessibilityIdentifier("workspace.inspector")
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch inspectorSection {
        case .assistant:
            AIChatPanelView()
        case .diagnostics:
            if appState.openDiagnosticCount == 0 {
                WorkspaceDiagnosticsQuietState(ollamaUnavailable: appState.isOllamaUnavailable)
            } else {
                DiagnosticsInspectorView()
            }
        case .watch:
            ActiveWatchPanel()
        case .pipeline:
            PipelineStatusView()
        case .context:
            ContextPreviewView()
        case .proposals:
            ProposalsInspectorView()
        case .search:
            WorkspaceSemanticSearchPanel()
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            IVBrandHeader(logoSize: 20, showWordmark: false)
        }
        ToolbarItemGroup(placement: .automatic) {
            Button {
                appState.showCommandPalette = true
            } label: {
                Label("Commands", systemImage: "command")
            }
            .buttonStyle(.ivIcon)
            .help("Command palette (⇧⌘K)")
            Button {
                appState.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.ivIcon)
            .help("Settings")
        }
    }
}

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        IVStatusBarChrome {
            HStack(spacing: IVLayout.statusBarItemSpacing) {
                IVStatusItem(text: appState.statusMessage, emphasis: true)
                IVStatusSeparator()
                saveStateLabel
                if !appState.activeSceneStatusLine.isEmpty {
                    IVStatusSeparator()
                    IVStatusItem(text: appState.activeSceneStatusLine)
                }
                Spacer(minLength: IVLayout.stackM)
                if appState.isTyping {
                    IVStatusItem(text: "Typing…")
                }
                if appState.queueStatus.pendingCount > 0 {
                    IVStatusItem(text: "Queue \(appState.queueStatus.pendingCount)")
                }
                if appState.analysisQueuePaused {
                    IVStatusItem(text: "LLM paused", warning: true)
                }
                if appState.openDiagnosticCount > 0 {
                    IVStatusItem(text: "\(appState.openDiagnosticCount) issues", warning: true)
                }
                if appState.isOllamaUnavailable, !appState.ollamaStatusText.isEmpty {
                    IVStatusItem(text: "Ollama off", warning: true)
                }
                if appState.isPipelineRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(IVColor.ivyUI)
                        .ivFireflyBreathing(active: true)
                }
                IVStatusItem(
                    text: "\(appState.activeDocument.map { TextUtilities.wordCount($0.plainText) } ?? 0) w",
                    emphasis: true
                )
            }
        }
        .accessibilityIdentifier("workspace.status")
    }

    @ViewBuilder
    private var saveStateLabel: some View {
        switch appState.documentSaveState {
        case .saved:
            IVStatusItem(text: "Saved", emphasis: true)
        case .unsaved:
            IVStatusItem(text: "Unsaved", warning: true)
        case .saving:
            IVStatusItem(text: "Saving…")
        case .saveError:
            IVStatusItem(text: "Save error", warning: true)
        }
    }
}

struct SceneExpansionSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var skeleton: String
    var isRunning: Bool
    var onSubmit: (String) -> Void
    @State private var outcome = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IVSheetHeaderBar(
                title: "Scene Expansion",
                subtitle: isRunning ? "Generation in progress — you can close this sheet." : nil,
                onDismiss: { dismiss() }
            )
            Text("Skeleton / beats").font(.headline)
            TextEditor(text: $skeleton).frame(height: 120)
            TextField("Required outcome", text: $outcome)
            if !appState.isSceneExpansionAvailable {
                Text("Ollama is unavailable — scene expansion is off. Deterministic checks still run from Analyze.")
                    .font(.caption)
                    .foregroundStyle(IVColor.diagnosticWarning)
            } else {
                Text("Ollama will draft prose as a change proposal. Nothing is applied automatically.")
                    .ivMutedCaption()
            }
            if isRunning {
                HStack {
                    ProgressView()
                        .tint(IVColor.ivyUI)
                        .ivFireflyBreathing(active: true)
                    Text("Generating…")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ivGhost)
                Button("Expand via Ollama") {
                    onSubmit(outcome)
                }
                .buttonStyle(.ivPrimary)
                .disabled(
                    skeleton.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isRunning
                        || !appState.isSceneExpansionAvailable
                )
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 520, height: 340)
        .ivSheetChrome()
        .onChange(of: isRunning) { _, running in
            if !running, appState.selectedProposal != nil {
                dismiss()
            }
        }
    }
}
