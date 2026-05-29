import SwiftUI

struct NarrativeMemoryView: View {
    @Environment(AppState.self) private var appState
    @State private var showAdd = false
    @State private var editingMemory: NarrativeMemory?
    @State private var draftSummary = ""
    @State private var draftScope: MemoryScope = .document
    @State private var draftThreads = ""
    @State private var pendingDeleteMemory: NarrativeMemory?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Memory & Summaries").font(.headline)
                Spacer()
                Button { beginAdd() } label: { Image(systemName: "plus") }
                    .buttonStyle(.ivIcon)
                Button("Refresh summaries") { appState.refreshSummaries() }
                    .buttonStyle(.ivGhost)
                    .font(.caption)
            }
            if appState.narrativeMemory.isEmpty {
                Text("No narrative memory stored. Summaries feed scoped analysis context.")
                    .ivMutedCaption()
            }
            List {
                ForEach(appState.narrativeMemory) { memory in
                    memoryRow(memory)
                        .ivFireflyRow(selected: editingMemory?.id == memory.id)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEdit(memory) }
                        .contextMenu {
                            Button("Delete…", role: .destructive) { pendingDeleteMemory = memory }
                        }
                }
            }
        }
        .confirmationDialog("Delete this memory entry?", isPresented: Binding(
            get: { pendingDeleteMemory != nil },
            set: { if !$0 { pendingDeleteMemory = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let m = pendingDeleteMemory { appState.deleteNarrativeMemory(id: m.id) }
                pendingDeleteMemory = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteMemory = nil }
        }
        .sheet(isPresented: $showAdd) { memoryEditorSheet(isNew: true) }
        .sheet(item: $editingMemory) { memory in
            memoryEditorSheet(isNew: false, existing: memory)
        }
    }

    private func memoryRow(_ memory: NarrativeMemory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(memory.scope.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(IVColor.forestHover.opacity(0.5))
                    .foregroundStyle(IVColor.chromeSecondary)
                    .clipShape(Capsule())
                if appState.isMemoryStale(memory) {
                    Text("stale")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(IVColor.diagnosticWarning.opacity(0.25))
                        .foregroundStyle(IVColor.diagnosticWarning)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(memory.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(IVColor.chromeTertiary)
            }
            Text(memory.summary).lineLimit(3)
            if !memory.openThreads.isEmpty {
                Text("\(memory.openThreads.count) open threads")
                    .font(.caption2)
                    .foregroundStyle(IVColor.diagnosticWarning)
            }
        }
        .padding(.vertical, 4)
    }

    private func beginAdd() {
        draftSummary = ""
        draftScope = .document
        draftThreads = ""
        showAdd = true
    }

    private func beginEdit(_ memory: NarrativeMemory) {
        editingMemory = memory
        draftSummary = memory.summary
        draftScope = memory.scope
        draftThreads = memory.openThreads.joined(separator: "\n")
    }

    private func memoryEditorSheet(isNew: Bool, existing: NarrativeMemory? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IVSheetHeaderBar(
                title: isNew ? "Add memory" : "Edit memory",
                onDismiss: {
                    showAdd = false
                    editingMemory = nil
                }
            )
            Picker("Scope", selection: $draftScope) {
                ForEach([MemoryScope.scene, .chapter, .document, .project], id: \.self) { s in
                    Text(s.rawValue.capitalized).tag(s)
                }
            }
            TextField("Summary", text: $draftSummary, axis: .vertical)
                .lineLimit(4...12)
            TextField("Open threads (one per line)", text: $draftThreads, axis: .vertical)
                .lineLimit(2...8)
            Text("Memory is source of truth. LLM may suggest updates; you approve them.")
                .ivMutedCaption()
            HStack {
                Spacer()
                Button("Cancel") {
                    showAdd = false
                    editingMemory = nil
                }
                Button("Save") {
                    saveMemory(isNew: isNew, existing: existing)
                    showAdd = false
                    editingMemory = nil
                }
                .disabled(draftSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 460, height: 360)
        .ivSheetChrome()
    }

    private func saveMemory(isNew: Bool, existing: NarrativeMemory?) {
        guard let projectID = appState.currentProject?.id else { return }
        let threads = draftThreads
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let scopeID = scopeID(for: draftScope)

        if isNew {
            let memory = NarrativeMemory(
                id: UUID(),
                projectID: projectID,
                scope: draftScope,
                scopeID: scopeID,
                summary: draftSummary,
                openThreads: threads,
                resolvedThreads: [],
                activeObjects: [],
                characterStates: [],
                atmospherePatterns: [],
                timelineNotes: [],
                sourceHash: appState.activeDocument.map { TextUtilities.hashText($0.plainText) },
                updatedAt: Date()
            )
            appState.addNarrativeMemory(memory)
        } else if var existing {
            existing.summary = draftSummary
            existing.scope = draftScope
            existing.scopeID = scopeID
            existing.openThreads = threads
            existing.updatedAt = Date()
            existing.sourceHash = appState.activeDocument.map { TextUtilities.hashText($0.plainText) }
            appState.updateNarrativeMemory(existing)
        }
    }

    private func scopeID(for scope: MemoryScope) -> UUID {
        switch scope {
        case .scene:
            return appState.structure.scenes.first?.id ?? appState.activeDocument?.id ?? UUID()
        case .chapter:
            return appState.structure.chapters.first?.id ?? appState.activeDocument?.id ?? UUID()
        case .document:
            return appState.activeDocument?.id ?? UUID()
        case .project:
            return appState.currentProject?.id ?? UUID()
        }
    }

}
