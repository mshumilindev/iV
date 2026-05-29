import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    private var navigationAccessibilityID: String {
        switch appState.navigation {
        case .library: "nav.library"
        case .projectOverview: "nav.overview"
        case .workspace: "nav.workspace"
        }
    }

    var body: some View {
        Group {
            switch appState.navigation {
            case .library:
                ProjectLibraryView()
            case .projectOverview:
                ProjectOverviewView()
            case .workspace:
                WorkspaceView()
            }
        }
        .accessibilityIdentifier(navigationAccessibilityID)
        .frame(minWidth: 1100, minHeight: 700)
        .ivAppChrome()
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .overlay {
            if appState.editorStartup.isLoading, let message = appState.editorStartup.loadingMessage {
                EditorStartupOverlay(message: message)
            }
        }
    }
}
