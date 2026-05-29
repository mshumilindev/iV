import SwiftUI

struct ManuscriptSnapshotsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [ManuscriptSnapshotRecord] = []
    @State private var loadError: String?
    @State private var pendingRestore: ManuscriptSnapshotRecord?
    @State private var createNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackM) {
            IVSheetHeaderBar(title: "Local snapshots", onDismiss: { dismiss() })
            Text("Recovery points for this manuscript. Restoring replaces the current text after saving a safety copy.")
                .font(.ivUICaption)
                .foregroundStyle(IVColor.chromeSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let loadError {
                Text(loadError).foregroundStyle(IVColor.diagnosticError).font(.ivUICaption)
            }

            List(snapshots) { snap in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snap.reason.displayName).font(.ivUIBody)
                        Spacer()
                        Text(snap.createdAt, style: .date)
                            .font(.ivUICaption)
                            .foregroundStyle(IVColor.chromeTertiary)
                    }
                    Text("\(snap.wordCount) words · \(snap.createdAt.formatted(date: .omitted, time: .shortened))")
                        .font(.ivUICaption)
                        .foregroundStyle(IVColor.chromeSecondary)
                    if let note = snap.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(IVColor.chromeTertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { pendingRestore = snap }
            }
            .frame(minHeight: 200)

            HStack {
                TextField("Note (optional)", text: $createNote)
                    .textFieldStyle(.roundedBorder)
                Button("Create checkpoint") {
                    appState.createManualSnapshot(note: createNote.isEmpty ? nil : createNote)
                    reload()
                    createNote = ""
                }
                .buttonStyle(.ivSecondary)
            }

        }
        .padding(IVLayout.windowHPadding)
        .frame(width: 480, height: 420)
        .onAppear { reload() }
        .confirmationDialog(
            "Restore this snapshot?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let snap = pendingRestore {
                    appState.restoreSnapshot(snap)
                    dismiss()
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Current manuscript text will be snapshotted first, then replaced with the selected version.")
        }
    }

    private func reload() {
        guard let folder = appState.currentFolder, let docID = appState.activeDocument?.id else { return }
        do {
            snapshots = try ManuscriptSnapshotStore.listSnapshots(documentID: docID, folder: folder)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
