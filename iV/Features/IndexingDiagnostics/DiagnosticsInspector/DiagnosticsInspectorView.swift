import SwiftUI

struct DiagnosticsInspectorView: View {
    @Environment(AppState.self) private var appState
    @State private var severityFilter: RuleSeverity?
    @State private var sourceFilter: DiagnosticSource?
    @State private var showStale = true
    @State private var confirmClearDiagnostics = false
    @State private var confirmClearHistory = false

    var filtered: [Diagnostic] {
        appState.diagnostics.filter { d in
            let sev = severityFilter == nil || d.severity == severityFilter
            let src = sourceFilter == nil || d.source == sourceFilter
            let stale = showStale || !d.isStale
            let active = d.status == .open || d.status == .stale
            return sev && src && stale && active
        }.sorted { $0.severity > $1.severity }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Severity", selection: $severityFilter) {
                    Text("All").tag(RuleSeverity?.none)
                    ForEach(RuleSeverity.allCases, id: \.self) { s in Text(s.rawValue).tag(Optional(s)) }
                }
                Picker("Source", selection: $sourceFilter) {
                    Text("All").tag(DiagnosticSource?.none)
                    ForEach([DiagnosticSource.deterministic, .llm, .pipeline], id: \.self) { s in
                        Text(s.rawValue).tag(Optional(s))
                    }
                }
            }
            .labelsHidden()
            Toggle("Show stale", isOn: $showStale)
                .font(.caption)
                .padding(.horizontal, 4)
            HStack {
                Button("Clear diagnostics…", role: .destructive) { confirmClearDiagnostics = true }
                    .buttonStyle(.ivGhost)
                    .font(.caption)
                Button("Clear run history…", role: .destructive) { confirmClearHistory = true }
                    .buttonStyle(.ivGhost)
                    .font(.caption)
            }
            .padding(.horizontal, 4)
            List(filtered) { diagnostic in
                DiagnosticRow(diagnostic: diagnostic)
                    .ivFireflyRow(selected: appState.selectedDiagnostic?.id == diagnostic.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.scrollToDiagnostic(diagnostic)
                        appState.selectedDiagnostic = diagnostic
                    }
                    .contextMenu {
                        Button("Details…") { appState.selectedDiagnostic = diagnostic }
                        Button("Ignore") { appState.setDiagnosticStatus(diagnostic.id, status: .ignored) }
                        Button("Resolve") { appState.setDiagnosticStatus(diagnostic.id, status: .resolved) }
                        if diagnostic.fixLevel == .safeAutoFix {
                            Button("Prepare safe fix") { appState.applySafeFix(for: diagnostic) }
                        }
                        if diagnostic.suggestedFix != nil {
                            Button("Create proposal") { appState.createProposalFromDiagnostic(diagnostic) }
                        }
                        Button("Deeper analysis") { appState.runDeeperAnalysis(for: diagnostic) }
                    }
            }
            .ivInspectorList()
        }
        .sheet(item: Bindable(appState).selectedDiagnostic) { diagnostic in
            DiagnosticDetailView(diagnostic: diagnostic).ivSheetChrome()
        }
        .confirmationDialog("Clear all diagnostics?", isPresented: $confirmClearDiagnostics, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { appState.clearAllDiagnostics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes diagnostics from the current document view (persisted store cleared).")
        }
        .confirmationDialog("Clear analysis run history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { appState.clearAnalysisRunHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct DiagnosticRow: View {
    let diagnostic: Diagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(diagnostic.severity.ivColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(diagnostic.title).font(.headline).foregroundStyle(IVColor.chromePrimary)
                    if diagnostic.isStale {
                        Text("stale")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(IVColor.diagnosticWarning.opacity(0.25))
                            .foregroundStyle(IVColor.diagnosticWarning)
                            .clipShape(Capsule())
                    }
                }
                if diagnostic.isStale, let reason = diagnostic.staleReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(IVColor.diagnosticWarning)
                        .lineLimit(2)
                }
                Text(diagnostic.message).font(.caption).lineLimit(2).ivSecondaryLabel()
                HStack(spacing: 6) {
                    Text(diagnostic.scope.rawValue).font(.caption2).foregroundStyle(IVColor.chromeTertiary)
                    if diagnostic.suggestedFix != nil {
                        Image(systemName: "wrench")
                            .font(.caption2)
                            .foregroundStyle(IVColor.diagnosticInfo)
                    }
                }
            }
        }
    }

    private var iconName: String {
        switch diagnostic.source {
        case .deterministic: "gearshape"
        case .llm: "cpu"
        case .pipeline: "arrow.triangle.branch"
        }
    }
}

/// Compact Active Watch panel — severity-sorted, source icons, one-line descriptions.
struct ActiveWatchPanel: View {
    @Environment(AppState.self) private var appState

    private var watchDiagnostics: [Diagnostic] {
        appState.diagnostics
            .filter { ($0.status == .open || $0.status == .stale) && !$0.isStale }
            .sorted { $0.severity > $1.severity }
            .prefix(40)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Active Watch").font(.headline).foregroundStyle(IVColor.chromePrimary)
                Spacer()
                if appState.queueStatus.isPaused {
                    Text(appState.analysisQueuePauseReason ?? "Paused")
                        .font(.caption2)
                        .foregroundStyle(IVColor.diagnosticWarning)
                } else if appState.queueStatus.isRunningLLM {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(IVColor.ivyUI)
                        .ivFireflyBreathing(active: true)
                }
            }
            .padding(.horizontal, 8)
            if !appState.activeWatchEnabled {
                Text("Enable Active Watch in the toolbar to stream diagnostics.")
                    .ivMutedCaption()
                    .padding(8)
            } else if watchDiagnostics.isEmpty {
                Text("No issues in current scope.").ivMutedCaption().padding(8)
            } else {
                List(watchDiagnostics) { diagnostic in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: diagnostic.source))
                            .font(.caption)
                            .foregroundStyle(diagnostic.severity.ivColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(diagnostic.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(diagnostic.message).font(.caption2).foregroundStyle(IVColor.chromeTertiary).lineLimit(1)
                        }
                    }
                    .ivFireflyRow(selected: appState.selectedDiagnostic?.id == diagnostic.id)
                    .onTapGesture {
                        appState.scrollToDiagnostic(diagnostic)
                        appState.selectedDiagnostic = diagnostic
                    }
                }
                .ivInspectorList()
            }
        }
    }

    private func icon(for source: DiagnosticSource) -> String {
        switch source {
        case .deterministic: "gearshape.fill"
        case .llm: "cpu"
        case .pipeline: "arrow.triangle.branch"
        }
    }
}
