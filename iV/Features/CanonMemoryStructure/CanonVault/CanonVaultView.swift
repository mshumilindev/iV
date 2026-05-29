import SwiftUI

struct CanonVaultView: View {
    @Environment(AppState.self) private var appState
    @State private var showAdd = false
    @State private var editingEntity: CanonEntity?
    @State private var newName = ""
    @State private var newType: CanonEntityType = .character
    @State private var newDescription = ""
    @State private var pendingDeleteEntity: CanonEntity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CanonSuggestionsView()
                Divider()
                HStack {
                    Text("Canon Vault").font(.headline)
                    Spacer()
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.ivIcon)
                }
                ForEach(appState.canonEntities) { entity in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entity.name).font(.headline)
                            Spacer()
                            Button("Edit") { beginEdit(entity) }
                                .buttonStyle(.ivGhost)
                                .font(.caption)
                            Button("Delete…", role: .destructive) { pendingDeleteEntity = entity }
                                .buttonStyle(.ivGhost)
                                .font(.caption)
                        }
                        Text(entity.type.rawValue).font(.caption).ivSecondaryLabel()
                        if !entity.description.isEmpty {
                            Text(entity.description).font(.caption).lineLimit(2)
                        }
                        if !entity.facts.isEmpty {
                            ForEach(entity.facts, id: \.self) { fact in
                                Text("• \(fact)").font(.caption2)
                            }
                        }
                    }
                    .ivFireflyRow(selected: editingEntity?.id == entity.id)
                    .padding(.vertical, 4)
                }
            }
            .padding(8)
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(item: $editingEntity) { entity in editSheet(entity) }
        .confirmationDialog(
            "Delete “\(pendingDeleteEntity?.name ?? "")” from canon?",
            isPresented: Binding(
                get: { pendingDeleteEntity != nil },
                set: { if !$0 { pendingDeleteEntity = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entity = pendingDeleteEntity { appState.deleteCanonEntity(id: entity.id) }
                pendingDeleteEntity = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteEntity = nil }
        }
    }

    private func beginEdit(_ entity: CanonEntity) {
        editingEntity = entity
        newName = entity.name
        newType = entity.type
        newDescription = entity.description
    }

    private var addSheet: some View {
        entityForm(title: "Add canon entity", submitLabel: "Add") {
            guard let projectID = appState.currentProject?.id else { return }
            appState.addCanonEntity(CanonEntity(
                id: UUID(),
                projectID: projectID,
                type: newType,
                name: newName,
                aliases: [],
                description: newDescription,
                facts: [],
                constraints: [],
                createdAt: Date(),
                updatedAt: Date()
            ))
            showAdd = false
            resetForm()
        } onCancel: { showAdd = false; resetForm() }
    }

    private func editSheet(_ entity: CanonEntity) -> some View {
        entityForm(title: "Edit canon entity", submitLabel: "Save") {
            var updated = entity
            updated.name = newName
            updated.type = newType
            updated.description = newDescription
            updated.updatedAt = Date()
            appState.updateCanonEntity(updated)
            editingEntity = nil
            resetForm()
        } onCancel: { editingEntity = nil; resetForm() }
    }

    private func entityForm(title: String, submitLabel: String, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IVSheetHeaderBar(title: title, onDismiss: onCancel)
            TextField("Name", text: $newName)
            Picker("Type", selection: $newType) {
                ForEach(CanonEntityType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            TextField("Description", text: $newDescription, axis: .vertical)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.ivGhost)
                Button(submitLabel, action: onSubmit)
                    .buttonStyle(.ivPrimary)
                    .disabled(newName.isEmpty)
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 400)
        .ivSheetChrome()
    }

    private func resetForm() {
        newName = ""
        newDescription = ""
        newType = .character
    }
}
