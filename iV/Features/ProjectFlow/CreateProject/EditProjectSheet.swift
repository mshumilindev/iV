import SwiftUI
import UniformTypeIdentifiers

struct EditProjectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let entry: ProjectRegistryEntry
    @State private var name: String
    @State private var subtitle: String
    @State private var coverURL: URL?
    @State private var removeCover = false
    @State private var confirmRemoveCover = false

    init(entry: ProjectRegistryEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _subtitle = State(initialValue: entry.subtitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IVSheetHeaderBar(title: "Edit Project", onDismiss: { dismiss() })
            Text(entry.folderURL.path)
                .font(.caption.monospaced())
                .ivMutedCaption()
                .lineLimit(2)
            TextField("Name", text: $name)
            TextField("Subtitle", text: $subtitle)
            HStack {
                Button("Choose Cover…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .webP, .image]
                    if panel.runModal() == .OK {
                        coverURL = panel.url
                        removeCover = false
                    }
                }
                if entry.coverImagePath != nil {
                    Button("Remove cover…", role: .destructive) { confirmRemoveCover = true }
                }
                Spacer()
                Text(coverLabel).ivMutedCaption()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ivGhost)
                Button("Save") {
                    appState.updateProject(
                        entry: entry,
                        name: name,
                        subtitle: subtitle,
                        newCoverURL: coverURL,
                        removeCover: removeCover
                    )
                    dismiss()
                }
                .buttonStyle(.ivPrimary)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 440)
        .confirmationDialog("Remove cover image?", isPresented: $confirmRemoveCover, titleVisibility: .visible) {
            Button("Remove cover", role: .destructive) { removeCover = true; coverURL = nil }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the cover file from the project covers folder.")
        }
    }

    private var coverLabel: String {
        if removeCover { return "Cover will be removed" }
        if let coverURL { return coverURL.lastPathComponent }
        if entry.coverImagePath != nil { return "Current cover kept" }
        return "No cover"
    }
}
