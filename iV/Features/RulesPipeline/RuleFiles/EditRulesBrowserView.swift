import SwiftUI

/// Standalone rules browser — library (global rules) or project workspace.
struct EditRulesBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFileID: UUID?
    @State private var searchText = ""
    @State private var categoryFilter: EditRuleCategory?
    @State private var sourceFilter: RuleSourceFilter = .all

    enum RuleSourceFilter: String, CaseIterable {
        case all = "All"
        case bundled = "Bundled"
        case project = "Project"
        case development = "Dev"

        var title: String { rawValue }
    }

    private var filteredFiles: [EditRuleFile] {
        appState.ruleFiles.filter { file in
            let matchesSearch = searchText.isEmpty
                || file.fileName.localizedCaseInsensitiveContains(searchText)
                || file.parsedSections.contains { $0.heading.localizedCaseInsensitiveContains(searchText) }
                || file.parsedSections.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
            let matchesCategory = categoryFilter == nil || file.detectedCategory == categoryFilter
            let matchesSource: Bool = {
                switch sourceFilter {
                case .all: return true
                case .bundled: return EditRuleLoader.source(for: file.path) == .bundled
                case .project: return EditRuleLoader.source(for: file.path) == .project
                case .development: return EditRuleLoader.source(for: file.path) == .development
                }
            }()
            return matchesSearch && matchesCategory && matchesSource
        }
    }

    var body: some View {
        NavigationSplitView {
            rulesSidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .background { IVWorkspaceCanvas() }
        .frame(minWidth: 900, minHeight: 580)
        .foregroundStyle(IVColor.chromePrimary)
        .tint(IVColor.ivyUI)
        .preferredColorScheme(.dark)
        .ivIntegratedChrome {
            IVBrandHeader(logoSize: 22)
        } trailing: {
            Button("Reload") { reloadRules() }
                .buttonStyle(.ivToolbar)
            if appState.currentFolder != nil {
                Button("Reveal") {
                    if let folder = appState.currentFolder {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            ProjectPaths.editRulesFolder(in: folder)
                        ])
                    }
                }
                .buttonStyle(.ivToolbar)
            }
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.ivToolbar)
        }
        .ivChromeFooter {
            rulesStatusBar
        }
        .onAppear {
            reloadRules()
            if selectedFileID == nil {
                selectedFileID = filteredFiles.first?.id
            }
        }
        .onChange(of: filteredFiles.count) { _, _ in
            if let id = selectedFileID, !filteredFiles.contains(where: { $0.id == id }) {
                selectedFileID = filteredFiles.first?.id
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let file = filteredFiles.first(where: { $0.id == selectedFileID }) ?? filteredFiles.first {
                RuleFileDetailPane(file: file)
            } else if appState.ruleFiles.isEmpty {
                IVEmptyWorkspaceState(
                    title: "No rule files loaded",
                    message: "Editorial rules load from the app bundle and project folder. Use Reload if the catalog did not appear.",
                    actionTitle: "Reload…",
                    action: reloadRules
                )
            } else {
                IVEmptyWorkspaceState(
                    title: "No rules match",
                    message: "No files match the current search or filter settings.",
                    actionTitle: "Reset filters",
                    action: clearFilters
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IVColor.forestBlack)
    }

    private var rulesSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: IVLayout.stackS) {
                IVSidebarHeader(title: "Edit Rules", subtitle: scopeDescription)
                TextField("Search rules…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Picker("Category", selection: $categoryFilter) {
                    Text("All categories").tag(EditRuleCategory?.none)
                    ForEach(EditRuleCategory.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(Optional(cat))
                    }
                }
                .labelsHidden()
                Picker("Source", selection: $sourceFilter) {
                    ForEach(RuleSourceFilter.allCases, id: \.self) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                Text("\(filteredFiles.count) of \(appState.ruleFiles.count) files")
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.chromeTertiary)
            }
            .padding(.horizontal, IVLayout.windowHPadding)
            .padding(.top, IVLayout.windowVPadding)
            .padding(.bottom, IVLayout.stackS)

            Divider().overlay(IVColor.forestHover.opacity(IVLayout.borderOpacity))

            List(filteredFiles, selection: $selectedFileID) { file in
                RuleFileRow(file: file)
                    .ivFireflyRow(selected: selectedFileID == file.id)
            }
            .ivInspectorList()
            .padding(.bottom, IVLayout.stackXS)
        }
        .ivForestPanel()
        .navigationSplitViewColumnWidth(min: IVLayout.sidebarMinWidth, ideal: IVLayout.sidebarIdealWidth)
    }

    private var rulesStatusBar: some View {
        IVStatusBarChrome {
            HStack(spacing: IVLayout.statusBarItemSpacing) {
                IVLogoView(size: 11).opacity(0.7)
                IVStatusItem(text: appState.statusMessage, emphasis: true)
                IVStatusSeparator()
                IVStatusItem(text: "\(appState.ruleFiles.count) loaded")
                IVStatusItem(text: "\(appState.ruleFiles.filter(\.enabled).count) enabled")
                Spacer()
                IVStatusItem(text: scopeDescriptionShort)
            }
        }
    }

    private var scopeDescription: String {
        if let project = appState.currentProject {
            return "Project: \(project.name) — bundled, dev, and project overrides merged by filename."
        }
        return "Global catalog — bundled app rules and local development copies."
    }

    private var scopeDescriptionShort: String {
        appState.currentProject?.name ?? "Global catalog"
    }

    private func reloadRules() {
        if appState.currentFolder != nil {
            appState.reloadProjectEditRules()
        } else {
            appState.ruleFiles = EditRuleLoader.loadAll()
            appState.statusMessage = "\(appState.ruleFiles.count) rule files loaded"
        }
        if selectedFileID == nil {
            selectedFileID = filteredFiles.first?.id
        }
    }

    private func clearFilters() {
        searchText = ""
        categoryFilter = nil
        sourceFilter = .all
    }
}

struct RuleFileRow: View {
    let file: EditRuleFile

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackXS) {
            HStack {
                Text(file.fileName)
                    .font(.ivUIBody)
                    .lineLimit(1)
                    .foregroundStyle(IVColor.chromePrimary)
                Spacer()
                if !file.enabled {
                    Text("off")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(IVColor.forestHover.opacity(0.5))
                        .foregroundStyle(IVColor.chromeTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            Text(file.detectedCategory.displayName)
                .font(.ivUICaption)
                .foregroundStyle(IVColor.chromeTertiary)
            HStack(spacing: IVLayout.stackS) {
                Label("\(file.parsedSections.count)", systemImage: "list.bullet")
                    .font(.ivUICaption)
                Text(sourceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(sourceColor)
            }
            .foregroundStyle(IVColor.chromeTertiary)
        }
        .padding(.vertical, IVLayout.stackXS)
    }

    private var sourceLabel: String {
        switch EditRuleLoader.source(for: file.path) {
        case .bundled: "bundled"
        case .project: "project"
        case .development: "dev"
        }
    }

    private var sourceColor: Color {
        switch EditRuleLoader.source(for: file.path) {
        case .bundled: IVColor.ivyUI
        case .project: IVColor.diagnosticInfo
        case .development: IVColor.diagnosticWarning
        }
    }
}

struct RuleFileDetailPane: View {
    @Environment(AppState.self) private var appState
    let file: EditRuleFile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IVLayout.stackL) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: IVLayout.stackXS) {
                        Text(file.fileName)
                            .font(.ivUIHeader)
                        Text(file.detectedCategory.displayName)
                            .font(.ivUICaption)
                            .foregroundStyle(IVColor.chromeTertiary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: bindingEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(IVColor.ivyUI)
                }
                Text(file.path)
                    .font(.ivMono)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .textSelection(.enabled)
                HStack(spacing: IVLayout.stackL) {
                    LabeledContent("Priority", value: "\(file.priority)")
                    LabeledContent("Sections", value: "\(file.parsedSections.count)")
                    LabeledContent("Source", value: EditRuleLoader.source(for: file.path).rawValue)
                }
                .font(.ivUICaption)
                Divider().overlay(IVColor.forestHover.opacity(IVLayout.borderOpacity))
                Text("Outline")
                    .font(.ivUIBody)
                    .foregroundStyle(IVColor.chromeSecondary)
                ForEach(file.parsedSections) { section in
                    DisclosureGroup {
                        Text(section.content)
                            .font(.ivManuscript)
                            .foregroundStyle(IVColor.documentText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(IVLayout.stackS)
                            .background(IVColor.documentSurface)
                            .clipShape(RoundedRectangle(cornerRadius: IVLayout.panelCornerRadius, style: .continuous))
                    } label: {
                        Text(section.heading)
                            .font(.ivUIBody)
                    }
                }
                Divider().overlay(IVColor.forestHover.opacity(IVLayout.borderOpacity))
                Text("Raw markdown")
                    .font(.ivUIBody)
                    .foregroundStyle(IVColor.chromeSecondary)
                Text(file.rawMarkdown)
                    .font(.ivMono)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, IVLayout.windowHPadding)
            .padding(.top, IVLayout.stackL)
            .padding(.bottom, IVLayout.stackM)
        }
        .ivChromeScrollContent()
        .background(IVColor.forestBlack)
    }

    private var bindingEnabled: Binding<Bool> {
        Binding(
            get: { appState.ruleFiles.first { $0.id == file.id }?.enabled ?? false },
            set: { appState.setRuleFileEnabled(file.id, enabled: $0) }
        )
    }
}
