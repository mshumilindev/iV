import SwiftUI

struct DiagnosticDetailView: View {
    @Environment(AppState.self) private var appState
    let diagnostic: Diagnostic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            GroupBox("Message") {
                Text(diagnostic.message).textSelection(.enabled)
            }
            if !diagnostic.evidence.isEmpty {
                GroupBox("Evidence") {
                    Text(diagnostic.evidence)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            metadataGrid
            if let fix = diagnostic.suggestedFix, !fix.isEmpty {
                GroupBox("Suggested fix") {
                    Text(fix).textSelection(.enabled)
                }
            }
            Spacer()
            actions
        }
        .padding(.horizontal, IVLayout.windowHPadding)
        .padding(.vertical, IVLayout.stackM)
        .ivChromeScrollContent()
        .frame(width: 520, height: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            IVSheetHeaderBar(title: diagnostic.title, onDismiss: { dismiss() })
            HStack(spacing: 8) {
                Label(diagnostic.severity.rawValue, systemImage: "flag")
                Label(diagnostic.source.rawValue, systemImage: sourceIcon)
                Label(diagnostic.scope.rawValue, systemImage: "scope")
            }
            .font(.caption)
            .ivSecondaryLabel()
            if diagnostic.isStale {
                Text("Stale: \(diagnostic.staleReason ?? "source changed")")
                    .font(.caption)
                    .foregroundStyle(IVColor.diagnosticWarning)
            }
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Status").ivSecondaryLabel()
                Text(diagnostic.status.rawValue)
            }
            GridRow {
                Text("Fix level").ivSecondaryLabel()
                Text(diagnostic.fixLevel.rawValue)
            }
        }
        .font(.caption)
    }

    private var actions: some View {
        HStack {
            Button("Ignore") {
                appState.setDiagnosticStatus(diagnostic.id, status: .ignored)
                dismiss()
            }
            Button("Resolve") {
                appState.setDiagnosticStatus(diagnostic.id, status: .resolved)
                dismiss()
            }
            Spacer()
            if diagnostic.fixLevel == .safeAutoFix {
                Button("Prepare safe fix") {
                    appState.applySafeFix(for: diagnostic)
                    dismiss()
                }
            }
            if diagnostic.suggestedFix != nil {
                Button("Create proposal") {
                    appState.createProposalFromDiagnostic(diagnostic)
                    dismiss()
                }
            }
            Button("Deeper analysis") {
                appState.runDeeperAnalysis(for: diagnostic)
                dismiss()
            }
            Button("Show in editor") {
                appState.scrollToDiagnostic(diagnostic)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var sourceIcon: String {
        switch diagnostic.source {
        case .deterministic: "gearshape"
        case .llm: "cpu"
        case .pipeline: "arrow.triangle.branch"
        }
    }
}
