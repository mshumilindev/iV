import Foundation

enum UITestSupport {
    /// Unit tests can set this to exercise UITest-only code paths without XCUITest.
    static var forceActiveForTesting = false

    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isActive: Bool {
        forceActiveForTesting
            || ProcessInfo.processInfo.arguments.contains("-UITest")
            || ProcessInfo.processInfo.environment["UITEST"] == "1"
    }

    static var shouldSeedProject: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestSeedProject")
            || ProcessInfo.processInfo.environment["UITEST_SEED_PROJECT"] == "1"
    }

    /// When true, AppState uses legacy NSTextView in-memory only (never persisted to UserDefaults).
    static var prefersInMemoryLegacyEditor: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestLegacyEditor")
            || ProcessInfo.processInfo.environment["UITEST_LEGACY_EDITOR"] == "1"
    }

    static var projectsRoot: URL {
        ProjectPaths.defaultProjectsRoot()
    }
}
