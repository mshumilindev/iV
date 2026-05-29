import SwiftUI

struct ContextPreviewView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            if let packet = appState.contextPacket {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Task", value: packet.task)
                    LabeledContent("Scope", value: packet.scope.rawValue)
                    GroupBox("Current text") {
                        Text(packet.currentText).font(.caption).textSelection(.enabled)
                    }
                    GroupBox("Rules (\(packet.relevantEditRules.count))") {
                        ForEach(packet.relevantEditRules, id: \.heading) { rule in
                            Text("[\(rule.fileName)] \(rule.heading)").font(.caption)
                        }
                    }
                    GroupBox("Canon (\(packet.relevantCanon.count))") {
                        ForEach(packet.relevantCanon) { entity in
                            Text(entity.name).font(.caption)
                        }
                    }
                }
                .padding()
            } else {
                IVEmptyWorkspaceState(
                    title: "No context packet",
                    message: "Build context from the Analysis menu to preview scoped rules and canon for the next pass."
                )
            }
        }
    }
}

struct ProposalsInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.proposals.filter { $0.status == .pending }) { proposal in
            Button(proposal.title) {
                appState.openProposalForReview(proposal)
            }
            .buttonStyle(.plain)
            .ivFireflyRow(selected: appState.selectedProposal?.id == proposal.id)
            .foregroundStyle(IVColor.chromePrimary)
        }
        .ivInspectorList()
    }
}

struct DiffReviewView: View {
    @Environment(AppState.self) private var appState
    let proposal: ChangeProposal
    @State private var editedAfter: String
    @State private var displayMode: DiffDisplayMode = .fullDiff
    @State private var confirmAccept = false

    init(proposal: ChangeProposal) {
        self.proposal = proposal
        _editedAfter = State(initialValue: proposal.afterText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $displayMode) {
                    Text("Read").tag(DiffDisplayMode.read)
                    Text("Light").tag(DiffDisplayMode.lightHighlight)
                    Text("Full diff").tag(DiffDisplayMode.fullDiff)
                }
                .pickerStyle(.segmented)
                .padding()

                HSplitView {
                    VStack(alignment: .leading) {
                        Text("Original").font(.headline)
                        ScrollView {
                            originalView
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Proposed").font(.headline)
                        if displayMode == .fullDiff {
                            TextEditor(text: $editedAfter).font(.body)
                        } else {
                            ScrollView { proposedView }
                        }
                    }
                }
                .padding()

                Text(proposal.reason).ivMutedCaption().padding(.horizontal)
                HStack {
                    Button("Reject") {
                        appState.rejectProposal(proposal)
                        appState.selectedProposal = nil
                    }
                    .buttonStyle(.ivGhost)
                    Spacer()
                    Button("Accept") {
                        if ProposalAcceptPolicy.requiresConfirmation(proposal) {
                            confirmAccept = true
                        } else {
                            acceptNow()
                        }
                    }
                    .buttonStyle(.ivPrimary)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, IVLayout.windowHPadding)
                .padding(.vertical, IVLayout.stackM)
            }
            .ivChromeScrollContent()
            .background(IVColor.forestBlack)
            .navigationTitle(proposal.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        appState.selectedProposal = nil
                        appState.revisionReviewActive = false
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .confirmationDialog("Apply this change to the manuscript?", isPresented: $confirmAccept, titleVisibility: .visible) {
            Button("Apply change", role: .destructive) { acceptNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This \(proposal.scope.rawValue)-level proposal will modify your manuscript. Review the diff carefully.")
        }
    }

    private func acceptNow() {
        appState.acceptProposal(proposal, editedAfter: editedAfter != proposal.afterText ? editedAfter : nil)
        appState.selectedProposal = nil
    }

    @ViewBuilder
    private var originalView: some View {
        switch displayMode {
        case .read:
            Text(proposal.beforeText).textSelection(.enabled)
        case .lightHighlight:
            Text(proposal.beforeText)
                .padding(4)
                .background(IVDiffColors.lightOriginal)
                .foregroundStyle(IVColor.documentText)
                .textSelection(.enabled)
        case .fullDiff:
            diffText(proposal.diff.filter { $0.kind != .inserted })
        }
    }

    @ViewBuilder
    private var proposedView: some View {
        switch displayMode {
        case .read:
            Text(proposal.afterText).textSelection(.enabled)
        case .lightHighlight:
            Text(proposal.afterText)
                .padding(4)
                .background(IVDiffColors.lightProposed)
                .foregroundStyle(IVColor.documentText)
                .textSelection(.enabled)
        case .fullDiff:
            diffText(proposal.diff)
        }
    }

    private func diffText(_ chunks: [TextDiffChunk]) -> some View {
        Text(attributedDiff(chunks))
            .textSelection(.enabled)
    }

    private func attributedDiff(_ chunks: [TextDiffChunk]) -> AttributedString {
        IVDiffAttributed.build(from: chunks)
    }
}
