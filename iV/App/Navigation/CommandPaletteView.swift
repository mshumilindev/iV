import SwiftUI

struct CommandPaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let shortcut: String?
    let action: () -> Void
}

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var highlightedID: UUID?
    @FocusState private var focused: Bool

    private var items: [CommandPaletteItem] {
        [
            CommandPaletteItem(title: "Close palette", subtitle: "Navigate", shortcut: "⎋") {
                dismiss()
            },
            CommandPaletteItem(title: "Run paragraph analysis", subtitle: "Analysis", shortcut: "⇧⌘R") {
                appState.runParagraphDiagnostics(); dismiss()
            },
            CommandPaletteItem(title: "Run scene analysis", subtitle: "Analysis", shortcut: nil) {
                appState.runSceneAnalysis(); dismiss()
            },
            CommandPaletteItem(title: "Run chapter analysis", subtitle: "Analysis", shortcut: nil) {
                appState.runChapterAnalysis(); dismiss()
            },
            CommandPaletteItem(title: "Run full pipeline", subtitle: "Analysis", shortcut: "⇧⌘P") {
                appState.runFullPipeline(); dismiss()
            },
            CommandPaletteItem(title: "Safe auto fix (review)", subtitle: "Analysis", shortcut: nil) {
                appState.runSafeAutoFix(); dismiss()
            },
            CommandPaletteItem(title: "Refresh summaries", subtitle: "Memory", shortcut: nil) {
                appState.refreshSummaries(); dismiss()
            },
            CommandPaletteItem(title: "Build context packet", subtitle: "Analysis", shortcut: nil) {
                appState.buildContextPreview(); dismiss()
            },
            CommandPaletteItem(title: "Reload edit rules", subtitle: "Rules", shortcut: nil) {
                appState.reloadEditRules(); dismiss()
            },
            CommandPaletteItem(title: "Find in manuscript", subtitle: "Edit", shortcut: "⌘F") {
                appState.findController.isVisible = true
                if let tv = appState.findController.textView { appState.findController.show(in: tv) }
                dismiss()
            },
            CommandPaletteItem(title: "Toggle focus mode", subtitle: "Editor", shortcut: nil) {
                appState.focusMode.toggle(); dismiss()
            },
            CommandPaletteItem(title: "Performance mode: Quiet", subtitle: "Editor", shortcut: nil) {
                appState.performanceMode = .quiet; dismiss()
            },
            CommandPaletteItem(title: "Performance mode: Balanced", subtitle: "Editor", shortcut: nil) {
                appState.performanceMode = .balanced; dismiss()
            },
            CommandPaletteItem(title: "Performance mode: Intensive", subtitle: "Editor", shortcut: nil) {
                appState.performanceMode = .intensive; dismiss()
            },
            CommandPaletteItem(title: "Reference pane: none", subtitle: "Editor", shortcut: nil) {
                appState.splitEditorReference = .none; dismiss()
            },
            CommandPaletteItem(title: "Reference pane: import snapshot", subtitle: "Editor", shortcut: nil) {
                appState.splitEditorReference = .importSnapshot; dismiss()
            },
            CommandPaletteItem(title: "Semantic search", subtitle: "Search", shortcut: nil) {
                appState.workspaceInspectorTab = .search; dismiss()
            },
            CommandPaletteItem(title: "Open settings", subtitle: "App", shortcut: nil) {
                appState.showSettings = true; dismiss()
            },
            CommandPaletteItem(title: "Project library", subtitle: "Navigate", shortcut: nil) {
                appState.navigation = .library; dismiss()
            },
            CommandPaletteItem(title: "Suggest chapter splits", subtitle: "Structure", shortcut: nil) {
                appState.suggestChapterSplits(); dismiss()
            },
            CommandPaletteItem(title: "Open existing project", subtitle: "Navigate", shortcut: nil) {
                appState.openExistingProjectFolder(); dismiss()
            },
            CommandPaletteItem(title: "Toggle Active Watch", subtitle: "Watch", shortcut: nil) {
                appState.activeWatchEnabled.toggle(); dismiss()
            },
            CommandPaletteItem(title: "Show Active Watch panel", subtitle: "Watch", shortcut: nil) {
                appState.activeWatchEnabled = true
                appState.workspaceInspectorTab = .watch
                dismiss()
            },
            CommandPaletteItem(title: "Edit rules browser", subtitle: "Rules", shortcut: nil) {
                appState.reloadProjectEditRules()
                appState.workspaceSidebarTab = .rules
                dismiss()
            }
        ]
    }

    private var filtered: [CommandPaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IVLogoView(size: 20)
                TextField("Command palette", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit {
                        if let id = highlightedID ?? filtered.first?.id,
                           let item = filtered.first(where: { $0.id == id }) {
                            item.action()
                        } else if let first = filtered.first {
                            first.action()
                        }
                    }
                IVSheetDismissButton(title: "Close", action: dismiss)
            }
            .padding(12)
            .ivEscapeToDismiss(dismiss)
            Divider().overlay(IVColor.forestHover.opacity(IVLayout.chromeDividerOpacity))
            List(filtered) { item in
                Button {
                    item.action()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title).foregroundStyle(IVColor.chromePrimary)
                            if let subtitle = item.subtitle {
                                Text(subtitle).ivMutedCaption()
                            }
                        }
                        Spacer()
                        if let shortcut = item.shortcut {
                            Text(shortcut).ivMutedCaption()
                        }
                    }
                }
                .buttonStyle(.plain)
                .ivFireflyRow(selected: highlightedID == item.id)
                .onHover { if $0 { highlightedID = item.id } }
                .listRowBackground(Color.clear)
            }
            .ivInspectorList()
            .frame(height: 280)
        }
        .padding(.vertical, IVLayout.chromeEdgeGap)
        .frame(width: 480)
        .background(IVColor.forestElevated)
        .clipShape(RoundedRectangle(cornerRadius: IVLayout.panelCornerRadius, style: .continuous))
        .onAppear {
            focused = true
            highlightedID = filtered.first?.id
        }
        .onChange(of: filtered.count) { _, _ in
            if let id = highlightedID, filtered.contains(where: { $0.id == id }) { return }
            highlightedID = filtered.first?.id
        }
        .onKeyPress(.upArrow) {
            moveHighlight(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveHighlight(by: 1)
            return .handled
        }
    }

    private func moveHighlight(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let ids = filtered.map(\.id)
        if let current = highlightedID, let idx = ids.firstIndex(of: current) {
            let next = (idx + delta + ids.count) % ids.count
            highlightedID = ids[next]
        } else {
            highlightedID = filtered.first?.id
        }
    }

    private func dismiss() {
        isPresented = false
        query = ""
        highlightedID = nil
    }
}
