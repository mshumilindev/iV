import SwiftUI

/// Inline side-by-side revision review (Read / Light / Full diff).
struct RevisionSplitView: View {
    @Environment(AppState.self) private var appState
    let proposal: ChangeProposal
    @State private var editedAfter: String
    @State private var displayMode: DiffDisplayMode
    @State private var confirmAccept = false

    init(proposal: ChangeProposal, displayMode: DiffDisplayMode? = nil) {
        self.proposal = proposal
        _editedAfter = State(initialValue: proposal.afterText)
        _displayMode = State(initialValue: displayMode ?? .lightHighlight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(IVColor.documentSecondary)
            HSplitView {
                pane(title: "Original", content: { originalContent })
                pane(title: "Proposed", content: { proposedContent })
            }
            Divider().overlay(IVColor.forestHover.opacity(0.5))
            footer
        }
        .background(IVColor.forestElevated)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title).font(.headline).foregroundStyle(IVColor.chromePrimary)
                Text(proposal.reason).ivMutedCaption().lineLimit(2)
            }
            Spacer()
            Picker("Mode", selection: $displayMode) {
                Text("Read").tag(DiffDisplayMode.read)
                Text("Light").tag(DiffDisplayMode.lightHighlight)
                Text("Diff").tag(DiffDisplayMode.fullDiff)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Label(proposal.riskLevel.rawValue, systemImage: "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(riskColor)
            Button {
                appState.selectedProposal = nil
                appState.revisionReviewActive = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Close")
                        .font(.caption)
                }
            }
            .buttonStyle(.ivIcon)
            .help("Close review")
        }
        .padding(10)
        .ivForestElevatedBar()
    }

    private func pane<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IVColor.documentMuted)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(IVColor.documentSurface)
        }
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private var originalContent: some View {
        switch displayMode {
        case .read:
            Text(proposal.beforeText).foregroundStyle(IVColor.documentText).textSelection(.enabled)
        case .lightHighlight:
            Text(proposal.beforeText)
                .padding(6)
                .background(IVDiffColors.lightOriginal)
                .foregroundStyle(IVColor.documentText)
                .textSelection(.enabled)
        case .fullDiff:
            diffText(proposal.diff.filter { $0.kind != .inserted })
        }
    }

    @ViewBuilder
    private var proposedContent: some View {
        switch displayMode {
        case .read:
            Text(editedAfter).foregroundStyle(IVColor.documentText).textSelection(.enabled)
        case .lightHighlight:
            Text(editedAfter)
                .padding(6)
                .background(IVDiffColors.lightProposed)
                .foregroundStyle(IVColor.documentText)
                .textSelection(.enabled)
        case .fullDiff:
            TextEditor(text: $editedAfter)
                .font(Font(IVTheme.manuscriptFont))
                .foregroundStyle(IVColor.documentText)
                .scrollContentBackground(.hidden)
                .background(IVColor.documentSurface)
        }
    }

    private var footer: some View {
        HStack {
            Button("Reject") {
                appState.rejectProposal(proposal)
                closeReview()
            }
            .buttonStyle(.ivGhost)
            Spacer()
            Text("Changes are not applied until you accept.")
                .font(.caption2)
                .foregroundStyle(IVColor.chromeTertiary)
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
        .padding(10)
        .ivForestElevatedBar()
        .confirmationDialog("Apply this change to the manuscript?", isPresented: $confirmAccept, titleVisibility: .visible) {
            Button("Apply change", role: .destructive) { acceptNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Large or high-risk proposal — confirm before applying to the manuscript.")
        }
    }

    private func acceptNow() {
        let edited = editedAfter != proposal.afterText ? editedAfter : nil
        appState.acceptProposal(proposal, editedAfter: edited)
        closeReview()
    }

    private func closeReview() {
        appState.selectedProposal = nil
        appState.revisionReviewActive = false
    }

    private func diffText(_ chunks: [TextDiffChunk]) -> some View {
        Text(IVDiffAttributed.build(from: chunks))
            .foregroundStyle(IVColor.documentText)
            .textSelection(.enabled)
    }

    private var riskColor: Color {
        switch proposal.riskLevel {
        case .low: IVColor.chromeTertiary
        case .medium: IVColor.diagnosticWarning
        case .high: IVColor.diagnosticError
        }
    }
}
