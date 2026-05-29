import SwiftUI

@main
struct iVApp: App {
    @NSApplicationDelegateAdaptor(IVAppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var didBootstrap = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .focusedSceneValue(\.appState, appState)
                .onAppear {
                    appDelegate.appState = appState
                    bootstrapOnce()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background || phase == .inactive {
                        appState.flushPendingSave()
                    }
                }
        }
        .commands {
            AppCommands()
        }
        .defaultSize(width: 1200, height: 800)
    }

    @MainActor
    private func bootstrapOnce() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if UITestSupport.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        appState.bootstrap()
        if !ProcessInfo.processInfo.environment.keys.contains("XCTestConfigurationFilePath") {
            appState.beginEmbeddedOfficeStartupIfNeeded()
        }
        if UITestSupport.isActive, UITestSupport.shouldSeedProject {
            appState.seedProjectForUITest()
        }
    }
}

private struct AppStateFocusedValueKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedValueKey.self] }
        set { self[AppStateFocusedValueKey.self] = newValue }
    }
}
