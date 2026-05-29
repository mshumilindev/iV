import SwiftUI

// MARK: - Column sizing (HSplitView)

enum WorkspaceLayout {
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 240
    static let sidebarMaxWidth: CGFloat = 300

    static let editorMinWidth: CGFloat = 360

    static let inspectorMinWidth: CGFloat = 280
    static let inspectorIdealWidth: CGFloat = 320
    static let inspectorMaxWidth: CGFloat = 420
}

// MARK: - Sidebar

enum WorkspaceSidebarSection: String, CaseIterable, Identifiable {
    case documents
    case structure
    case rules
    case canon
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: "Documents"
        case .structure: "Structure"
        case .rules: "Rules"
        case .canon: "Canon"
        case .memory: "Memory"
        }
    }

    var systemImage: String {
        switch self {
        case .documents: "doc.text"
        case .structure: "list.bullet.indent"
        case .rules: "text.book.closed"
        case .canon: "books.vertical"
        case .memory: "brain.head.profile"
        }
    }

    /// Primary writing navigation — shown without grouping.
    var isPrimary: Bool {
        self == .documents || self == .structure
    }
}

struct WorkspaceSidebarNav: View {
    @Binding var selection: WorkspaceSidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackXS) {
            if selection != .documents {
                Button {
                    selection = .documents
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Documents")
                            .font(.ivUICaption)
                    }
                    .foregroundStyle(IVColor.chromeSecondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, IVLayout.stackXS)
            }
            ForEach(WorkspaceSidebarSection.allCases.filter(\.isPrimary)) { section in
                navButton(section)
            }
            Rectangle()
                .fill(IVColor.forestHover.opacity(IVLayout.chromeDividerOpacity))
                .frame(height: 1)
                .padding(.vertical, IVLayout.stackXS)
            ForEach(WorkspaceSidebarSection.allCases.filter { !$0.isPrimary }) { section in
                navButton(section)
            }
        }
        .padding(.horizontal, IVLayout.stackS)
        .padding(.top, IVLayout.stackS)
    }

    private func navButton(_ section: WorkspaceSidebarSection) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(section.title)
                    .font(.ivUIBody)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: IVLayout.buttonCornerRadius, style: .continuous)
                    .fill(selection == section ? IVColor.forestHover.opacity(0.35) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IVLayout.buttonCornerRadius, style: .continuous)
                    .stroke(
                        selection == section ? IVColor.fireflyWarm.opacity(0.45) : .clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(IVColor.chromePrimary)
    }
}

struct WorkspaceStructureSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var structureMode: StructureMode = .scenes

    enum StructureMode: String, CaseIterable {
        case chapters, scenes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Structure", selection: $structureMode) {
                ForEach(StructureMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            switch structureMode {
            case .chapters:
                List {
                    ForEach(appState.structure.chapters) { ch in
                        Button(ch.title) {
                            if let pid = ch.startParagraphID { appState.jumpToParagraph(pid) }
                        }
                        .buttonStyle(.plain)
                        .ivFireflyRow()
                    }
                    if appState.structure.chapters.isEmpty {
                        Text("No chapters detected yet.")
                            .ivMutedCaption()
                    }
                }
                .ivInspectorList()
            case .scenes:
                SceneIndexPanelView()
            }
        }
    }
}

// MARK: - Inspector

enum WorkspaceInspectorSection: String, CaseIterable, Identifiable {
    case assistant
    case diagnostics
    case watch
    case pipeline
    case proposals
    case context
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: "Assistant"
        case .diagnostics: "Diagnostics"
        case .watch: "Watch"
        case .pipeline: "Pipeline"
        case .proposals: "Proposals"
        case .context: "Context"
        case .search: "Search"
        }
    }

    var isPrimary: Bool { self == .assistant || self == .diagnostics }

    var isSecondary: Bool { !isPrimary }
}

struct WorkspaceInspectorNav: View {
    @Binding var selection: WorkspaceInspectorSection
    var openIssueCount: Int
    var onHideInspector: () -> Void

    var body: some View {
        HStack(spacing: IVLayout.stackS) {
            ForEach(WorkspaceInspectorSection.allCases.filter(\.isPrimary)) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 4) {
                        Text(section.title)
                            .font(.ivUIBody)
                        if section == .diagnostics, openIssueCount > 0 {
                            Text("\(openIssueCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(IVColor.diagnosticWarning.opacity(0.25))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? IVColor.chromePrimary : IVColor.chromeSecondary)
            }

            Menu {
                ForEach(WorkspaceInspectorSection.allCases.filter(\.isSecondary)) { section in
                    Button(section.title) { selection = section }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection == .diagnostics ? "More" : selection.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.ivUICaption)
                .foregroundStyle(IVColor.chromeSecondary)
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button(action: onHideInspector) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Close")
                        .font(.ivUICaption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(IVColor.chromeSecondary)
            .help("Hide inspector")
        }
        .padding(.horizontal, IVLayout.stackS)
        .padding(.top, IVLayout.stackS)
    }
}

struct WorkspaceDiagnosticsQuietState: View {
    let ollamaUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackS) {
            Text("No open issues")
                .font(.ivUIBody)
                .foregroundStyle(IVColor.chromePrimary)
            Text("Deterministic checks run from the Analyze menu or when you edit. Results appear here when found.")
                .font(.ivUICaption)
                .foregroundStyle(IVColor.chromeSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if ollamaUnavailable {
                Text("Ollama is unavailable — LLM passes are off; mechanical rules still work.")
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.diagnosticWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(IVLayout.stackM)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorkspaceSemanticSearchPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackS) {
            Text("Semantic search")
                .font(.ivUIBody)
                .foregroundStyle(IVColor.chromeSecondary)
            Text("Search indexed paragraphs when embeddings are enabled in Settings.")
                .font(.ivUICaption)
                .foregroundStyle(IVColor.chromeTertiary)
            TextField("Search project…", text: Bindable(appState).semanticSearchQuery)
                .textFieldStyle(.roundedBorder)
            Button("Search") { appState.runSemanticSearch() }
                .buttonStyle(.ivSecondary)
            List(appState.semanticSearchResults, id: \.self) { paragraphID in
                Button(paragraphID.uuidString.prefix(8) + "…") {
                    appState.jumpToParagraph(paragraphID)
                }
                .buttonStyle(.plain)
                .ivFireflyRow()
            }
            .ivInspectorList()
            Text("Index: \(appState.semanticIndexModeLabel)")
                .ivMutedCaption()
            Button("Update index (dirty only)") { appState.rebuildSemanticIndex(fullRebuild: false) }
                .buttonStyle(.ivGhost)
                .font(.caption)
            Button("Full rebuild index") { appState.rebuildSemanticIndex(fullRebuild: true) }
                .buttonStyle(.ivGhost)
                .font(.caption)
        }
        .padding(IVLayout.stackS)
    }
}

// MARK: - Editor chrome

struct WorkspaceEditorChrome: View {
    @Environment(AppState.self) private var appState
    @Binding var showSceneExpansion: Bool
    var openIssueCount: Int
    var onToggleInspector: () -> Void
    var inspectorVisible: Bool
    var onShowAssistant: () -> Void
    var onEditRules: () -> Void

    var body: some View {
        HStack(spacing: IVLayout.stackS) {
            Button {
                if let id = appState.currentProject?.id {
                    appState.navigation = .projectOverview(id)
                } else {
                    appState.navigation = .library
                }
            } label: {
                Label("Project", systemImage: "chevron.left")
            }
            .buttonStyle(.ivSecondary)
            .accessibilityIdentifier("workspace.backToProject")
            .help("Back to project overview")

            Button("Library") {
                appState.navigation = .library
            }
            .buttonStyle(.ivGhost)
            .accessibilityIdentifier("workspace.library")
            .help("All projects")

            if let project = appState.currentProject {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IVColor.chromeTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: IVLayout.stackM)

            Button {
                onShowAssistant()
            } label: {
                Label("Assistant", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.ivGhost)
            .accessibilityIdentifier("workspace.assistant")
            .help("Open AI assistant (selection-aware chat)")

            Button {
                onToggleInspector()
            } label: {
                HStack(spacing: 4) {
                    Label(
                        "Inspector",
                        systemImage: inspectorVisible ? "sidebar.right.fill" : "sidebar.right"
                    )
                    if openIssueCount > 0 {
                        Text("\(openIssueCount)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            }
            .buttonStyle(.ivGhost)
            .accessibilityIdentifier("workspace.inspectorToggle")
            .help(inspectorVisible ? "Hide diagnostics & tools panel" : "Show diagnostics, pipeline, proposals…")

            Button {
                appState.findController.isVisible.toggle()
                if appState.findController.isVisible, let tv = appState.findController.textView {
                    appState.findController.show(in: tv)
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.ivGhost)
            .help("Find (⌘F)")

            Menu {
                Toggle("Focus mode", isOn: Bindable(appState).focusMode)
                Toggle("Active Watch", isOn: Bindable(appState).activeWatchEnabled)
                Divider()
                Button("Snapshots…") { appState.showManuscriptSnapshots = true }
                Menu("Reference pane") {
                    ForEach(SplitEditorReference.allCases, id: \.self) { mode in
                        Button(mode.label) { appState.splitEditorReference = mode }
                    }
                }
                Divider()
                Button("Edit Rules…", action: onEditRules)
                Button("Open Settings…") { appState.showSettings = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Writing options")

            Menu("Analyze") {
                Button("Selection") { appState.runSelectionAnalysis() }
                Button("Paragraph") { appState.runParagraphDiagnostics() }
                Button("Scene") { appState.runSceneAnalysis() }
                Button("Chapter") { appState.runChapterAnalysis() }
                Divider()
                Button("Full pipeline") { appState.runFullPipeline() }
                    .accessibilityIdentifier("workspace.pipeline")
                Button("Safe fix (review)") { appState.runSafeAutoFix() }
                Button("Scene expansion…") { showSceneExpansion = true }
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("workspace.analyze")
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, 6)
    }
}
