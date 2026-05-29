import SwiftUI
import UniformTypeIdentifiers

struct ProjectLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreate = false
    @State private var showRulesBrowser = false
    @State private var editingEntry: ProjectRegistryEntry?
    @State private var pendingDelete: ProjectRegistryEntry?
    @State private var newName = ""
    @State private var newSubtitle = ""
    @State private var coverURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                    if appState.registryUnavailable {
                        IVEmptyWorkspaceState(
                            title: "Library unavailable",
                            message: appState.registryUnavailableMessage
                                ?? "The project registry could not be read. Your projects were not deleted — repair or restore projects.json and retry.",
                            actionTitle: "Retry",
                            action: { appState.bootstrap() }
                        )
                        .accessibilityIdentifier("library.registryError")
                    } else if appState.projects.isEmpty {
                        IVEmptyWorkspaceState(
                            title: "No projects",
                            message: "Your local library is empty. Projects stay on this Mac — create one or open an existing project folder.",
                            actionTitle: "Create project…",
                            action: { showCreate = true }
                        )
                        .accessibilityIdentifier("library.empty")
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 248), spacing: IVLayout.stackM)],
                                spacing: IVLayout.stackM
                            ) {
                                ForEach(appState.projects) { entry in
                                    ProjectCardView(
                                        entry: entry,
                                        onOpen: { appState.openProject(entry: entry) },
                                        onEdit: { editingEntry = entry },
                                        onDuplicate: { appState.duplicateProject(entry) },
                                        onRevealInFinder: {
                                            NSWorkspace.shared.activateFileViewerSelecting([entry.folderURL])
                                        },
                                        onDelete: { pendingDelete = entry }
                                    )
                                    .contextMenu {
                                        projectContextMenu(for: entry)
                                    }
                                }
                            }
                            .padding(.horizontal, IVLayout.workspaceInsetH + IVLayout.stackS)
                            .padding(.top, IVLayout.stackM)
                            .padding(.bottom, IVLayout.stackL)
                            .ivChromeScrollContent()
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { IVWorkspaceCanvas() }
            .navigationTitle("")
            .accessibilityIdentifier("library.root")
            .ivIntegratedChrome {
                IVBrandHeader(logoSize: 22)
            } trailing: {
                Button("Open…") { appState.openExistingProjectFolder() }
                    .buttonStyle(.ivToolbar)
                Button("New Project") { showCreate = true }
                    .buttonStyle(.ivToolbarAccent)
                    .accessibilityIdentifier("library.newProject")
                    .accessibilityLabel("New Project")
                Button("Rules") {
                    appState.reloadEditRules()
                    showRulesBrowser = true
                }
                .buttonStyle(.ivToolbar)
                .accessibilityIdentifier("library.editRules")
            }
            .ivChromeFooter {
                StatusBarView()
            }
        }
        .sheet(isPresented: $showCreate) {
            createSheet
                .ivSheetChrome()
                .onAppear { newName = ""; newSubtitle = ""; coverURL = nil }
        }
        .sheet(item: $editingEntry) { entry in EditProjectSheet(entry: entry).ivSheetChrome() }
        .sheet(isPresented: $showRulesBrowser) {
            EditRulesBrowserView()
                .ivSheetChrome()
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let entry = pendingDelete { appState.deleteProject(entry) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the project folder from disk. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func projectContextMenu(for entry: ProjectRegistryEntry) -> some View {
        Button("Open") { appState.openProject(entry: entry) }
        Button("Edit…") { editingEntry = entry }
        Button("Duplicate") { appState.duplicateProject(entry) }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([entry.folderURL])
        }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = entry }
    }

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackM) {
            IVSheetHeaderBar(title: "New Project", onDismiss: { showCreate = false })
            TextField("Name", text: $newName)
                .accessibilityIdentifier("createProject.name")
            TextField("Subtitle", text: $newSubtitle)
                .accessibilityIdentifier("createProject.subtitle")
            HStack {
                Button("Choose Cover…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .webP, .image]
                    if panel.runModal() == .OK { coverURL = panel.url }
                }
                .buttonStyle(.ivSecondary)
                Text(coverURL?.lastPathComponent ?? "No cover")
                    .ivMutedCaption()
            }
            HStack {
                Spacer()
                Button("Cancel") { showCreate = false }
                    .buttonStyle(.ivGhost)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    appState.createProject(name: name, subtitle: newSubtitle, coverURL: coverURL)
                    guard appState.errorMessage == nil else { return }
                    showCreate = false
                    newName = ""
                    newSubtitle = ""
                    coverURL = nil
                }
                .buttonStyle(.ivPrimary)
                .accessibilityIdentifier("createProject.submit")
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 420)
    }
}

struct ProjectCardView: View {
    let entry: ProjectRegistryEntry
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onRevealInFinder: () -> Void
    var onDelete: () -> Void

    private var folderIsValid: Bool {
        ProjectStore.projectFolderIsValid(entry.folderURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackS) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: IVLayout.cardCornerRadius, style: .continuous)
                        .fill(IVColor.forestDeep)
                        .frame(height: 132)
                    if let coverPath = entry.coverImagePath {
                        let url = entry.folderURL.appendingPathComponent("covers").appendingPathComponent(coverPath)
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().scaledToFill().frame(height: 132).clipped()
                        } else {
                            placeholder
                        }
                    } else {
                        placeholder
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: IVLayout.cardCornerRadius, style: .continuous))

                Menu {
                    Button("Open") { onOpen() }
                    Button("Edit…") { onEdit() }
                    Button("Duplicate") { onDuplicate() }
                    Button("Reveal in Finder") { onRevealInFinder() }
                    Divider()
                    Button("Delete…", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(IVColor.chromePrimary, IVColor.forestElevated.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .padding(8)
                .accessibilityLabel("Project actions")
                .accessibilityIdentifier("library.projectMenu.\(entry.id.uuidString)")
            }

            Text(entry.name).font(.ivUIBody).foregroundStyle(IVColor.chromePrimary)
            if !folderIsValid {
                Text("Project folder missing — remove from library")
                    .font(.ivUICaption)
                    .foregroundStyle(IVColor.diagnosticWarning)
            } else if !entry.subtitle.isEmpty {
                Text(entry.subtitle).font(.ivUICaption).foregroundStyle(IVColor.chromeTertiary)
            }
            HStack {
                Text("\(entry.wordCount) words")
                Spacer()
                if let edited = entry.lastEdited {
                    Text(edited, style: .date)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(IVColor.chromeTertiary)
        }
        .ivLibraryCard()
        .ivFireflyCard()
        .contentShape(RoundedRectangle(cornerRadius: IVLayout.cardCornerRadius, style: .continuous))
        .opacity(folderIsValid ? 1 : 0.55)
        .onTapGesture {
            if folderIsValid { onOpen() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(folderIsValid ? "Open \(entry.name)" : "\(entry.name), folder missing, remove from library")
    }

    private var placeholder: some View {
        IVLogoView(size: 36)
            .opacity(0.32)
    }
}
