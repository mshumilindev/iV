import SwiftUI

struct ProjectOverviewView: View {
    @Environment(AppState.self) private var appState
    @State private var showRulesBrowser = false
    @State private var editingEntry: ProjectRegistryEntry?
    @State private var pendingDelete = false
    @State private var pendingImportReplace: DocumentImportService?

    var body: some View {
        NavigationStack {
            if let project = appState.currentProject, let folder = appState.currentFolder {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 20) {
                            coverView(project: project, folder: folder)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(project.name).font(.largeTitle).foregroundStyle(IVColor.chromePrimary)
                                if !project.subtitle.isEmpty {
                                    Text(project.subtitle).ivSecondaryLabel()
                                }
                                Text("\(project.wordCount ?? 0) words")
                                Text(appState.ollamaStatusText).ivMutedCaption()
                            }
                        }
                        diagnosticsSummary
                        actionButtons
                        documentsSection
                    }
                    .padding(IVLayout.windowHPadding)
                    .ivChromeScrollContent()
                }
                .background { IVWorkspaceCanvas() }
                .navigationTitle("")
                .ivIntegratedChrome {
                    HStack(spacing: IVLayout.stackM) {
                        IVBrandHeader(logoSize: 22, showWordmark: false)
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(IVColor.chromeTertiary)
                            .lineLimit(1)
                    }
                } trailing: {
                    Button("Library") { appState.navigation = .library }
                        .buttonStyle(.ivToolbar)
                    Menu("Project") {
                        if let entry = appState.projects.first(where: { $0.id == project.id }) {
                            Button("Edit…") { editingEntry = entry }
                            Button("Duplicate") { appState.duplicateProject(entry) }
                            Button("Delete…", role: .destructive) { pendingDelete = true }
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
                .ivChromeFooter {
                    StatusBarView()
                }
                .sheet(isPresented: $showRulesBrowser) { EditRulesBrowserView().ivSheetChrome() }
                .sheet(item: $editingEntry) { entry in EditProjectSheet(entry: entry).ivSheetChrome() }
                .confirmationDialog("Delete “\(project.name)”?", isPresented: $pendingDelete, titleVisibility: .visible) {
                    Button("Delete Project", role: .destructive) {
                        if let entry = appState.projects.first(where: { $0.id == project.id }) {
                            appState.deleteProject(entry)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the project folder from disk. This cannot be undone.")
                }
                .confirmationDialog("Replace active manuscript?", isPresented: Binding(
                    get: { pendingImportReplace != nil },
                    set: { if !$0 { pendingImportReplace = nil } }
                ), titleVisibility: .visible) {
                    Button("Replace", role: .destructive) {
                        if let service = pendingImportReplace {
                            appState.importManuscript(service: service, replaceActive: true)
                        }
                        pendingImportReplace = nil
                    }
                    Button("Cancel", role: .cancel) { pendingImportReplace = nil }
                } message: {
                    Text("Overwrites the current document text with the imported file.")
                }
            } else {
                IVEmptyWorkspaceState(
                    title: "Project unavailable",
                    message: "This project could not be loaded. Return to the library or open another project.",
                    actionTitle: "Library",
                    action: { appState.navigation = .library }
                )
                .navigationTitle("")
                .ivIntegratedChrome {
                    IVBrandHeader(logoSize: 22, showWordmark: false)
                } trailing: {
                    Button("Library") { appState.navigation = .library }
                        .buttonStyle(.ivToolbar)
                }
            }
        }
        .accessibilityIdentifier("nav.overview")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func coverView(project: Project, folder: URL) -> some View {
        let size: CGFloat = 160
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(IVColor.forestDeep)
            .frame(width: size, height: size)
            .overlay {
                if let coverPath = project.coverImagePath {
                    let url = ProjectPaths.coversFolder(in: folder).appendingPathComponent(coverPath)
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        IVLogoView(size: 48).opacity(0.5)
                    }
                } else {
                    IVLogoView(size: 48).opacity(0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var diagnosticsSummary: some View {
        let s = appState.currentProject?.diagnosticsSummary ?? .empty
        return HStack(spacing: 16) {
            Label("\(s.blocking) blocking", systemImage: "exclamationmark.octagon")
                .foregroundStyle(IVColor.diagnosticBlocking)
            Label("\(s.errors) errors", systemImage: "xmark.circle")
                .foregroundStyle(IVColor.diagnosticError)
            Label("\(s.warnings) warnings", systemImage: "exclamationmark.triangle")
                .foregroundStyle(IVColor.diagnosticWarning)
            Label("\(s.pendingProposals) proposals", systemImage: "arrow.left.arrow.right")
                .foregroundStyle(IVColor.ivySoft)
        }
        .font(.subheadline)
    }

    private var actionButtons: some View {
        HStack {
            Button("Open Editor") { appState.openEditor() }
                .buttonStyle(.ivToolbarAccent)
                .accessibilityIdentifier("overview.openEditor")
                .accessibilityLabel("Open Editor")
                .keyboardShortcut(.return, modifiers: .command)
            Menu("Import Manuscript") {
                importMenuButton(PlainTextImportService(), replace: false)
                importMenuButton(RTFImportService(), replace: false)
                importMenuButton(DOCXImportService(), replace: false)
                Divider()
                importMenuButton(PlainTextImportService(), replace: true)
                importMenuButton(DOCXImportService(), replace: true)
            }
            Button("Run Full Analysis") { appState.runFullPipeline() }
                .buttonStyle(.ivSecondary)
            Button("Create Manuscript") { appState.createAdditionalManuscript() }
                .buttonStyle(.ivSecondary)
            Button("Canon Vault") { appState.openCanonVault() }
                .buttonStyle(.ivSecondary)
            Button("Edit Rules…") {
                appState.reloadProjectEditRules()
                showRulesBrowser = true
            }
            .buttonStyle(.ivSecondary)
        }
    }

    private func importMenuButton<S: DocumentImportService>(_ service: S, replace: Bool) -> some View {
        let label = replace ? "Replace active — \(service.menuLabel)…" : "Import \(service.menuLabel) (new doc)…"
        return Button(label) {
            if replace {
                pendingImportReplace = service
            } else {
                appState.importManuscript(service: service)
            }
        }
        .disabled(!service.isAvailable)
        .help(service.limitationSummary)
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Documents").font(.title2).foregroundStyle(IVColor.chromePrimary)
            ForEach(appState.documents) { doc in
                Button(doc.title) {
                    appState.loadDocument(doc)
                    appState.openEditor()
                }
                .buttonStyle(.plain)
                .ivFireflyRow(selected: appState.activeDocument?.id == doc.id)
                .foregroundStyle(IVColor.chromePrimary)
            }
        }
    }
}
