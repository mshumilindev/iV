import SwiftUI

/// Compact rules panel inside workspace sidebar; full browser via sheet.
struct RuleFilesView: View {
    @Environment(AppState.self) private var appState
    @State private var showBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edit rules").font(.headline)
                Spacer()
                Button("Browse…") { showBrowser = true }
                    .buttonStyle(.ivGhost)
                Button("Reload") { appState.reloadProjectEditRules() }
                    .buttonStyle(.ivGhost)
            }
            .padding(.horizontal, 8)
            if appState.ruleFiles.isEmpty {
                VStack(alignment: .leading, spacing: IVLayout.stackS) {
                    Text("No rules loaded")
                        .font(.ivUIBody)
                        .foregroundStyle(IVColor.chromePrimary)
                    Text("Reload copies bundled defaults into the project when the edit-rules folder is empty.")
                        .font(.ivUICaption)
                        .foregroundStyle(IVColor.chromeSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: IVLayout.stackS) {
                        Button("Load defaults") { appState.reloadProjectEditRules() }
                            .buttonStyle(.ivSecondary)
                        Button("Browse all…") { showBrowser = true }
                            .buttonStyle(.ivGhost)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            } else {
                Text("\(appState.ruleFiles.filter(\.enabled).count) enabled · \(appState.ruleFiles.count) loaded")
                    .font(.caption2)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .padding(.horizontal, 8)
                List(appState.ruleFiles) { file in
                    RuleFileRow(file: file)
                        .ivFireflyRow()
                }
                .ivInspectorList()
            }
        }
        .sheet(isPresented: $showBrowser) {
            EditRulesBrowserView().ivSheetChrome()
        }
    }
}
