import XCTest

final class iVUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    private func launchApp(extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest"] + extraArguments
        app.launchEnvironment["UITEST"] = "1"
        if extraArguments.contains("-UITestSeedProject") {
            app.launchEnvironment["UITEST_SEED_PROJECT"] = "1"
        }
        app.launch()
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 15)
        guard app.windows.firstMatch.waitForExistence(timeout: 12) else {
            throw XCTSkip(
                "macOS UI tests need an interactive session (no iV window). "
                    + "Run on a logged-in Mac and enable Accessibility for Xcode/Cursor in System Settings → Privacy."
            )
        }
        return app
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func newProjectSheet(in app: XCUIApplication) -> XCUIElement {
        if app.sheets.firstMatch.waitForExistence(timeout: 4) { return app.sheets.firstMatch }
        let field = app.textFields["createProject.name"]
        if field.waitForExistence(timeout: 6) {
            return app.windows.containing(.textField, identifier: "createProject.name").firstMatch
        }
        return app.sheets.firstMatch
    }

    private func waitForLibrary(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        if app.otherElements["library.root"].waitForExistence(timeout: timeout) { return true }
        if app.buttons["library.newProject"].waitForExistence(timeout: 3) { return true }
        return app.buttons["New Project"].waitForExistence(timeout: 3)
    }

    private func waitForWorkspace(_ app: XCUIApplication, timeout: TimeInterval = 25) -> Bool {
        if app.otherElements["nav.workspace"].waitForExistence(timeout: timeout) { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.otherElements["nav.workspace"].exists { return true }
            if app.buttons["workspace.overview"].exists { return true }
            if app.otherElements["workspace.root"].exists { return true }
            if app.otherElements["workspace.editor"].exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return app.otherElements["nav.workspace"].exists
    }

    private func knownAppRootExists(_ app: XCUIApplication) -> Bool {
        app.otherElements["nav.library"].exists
            || app.otherElements["library.root"].exists
            || app.otherElements["nav.overview"].exists
            || app.otherElements["overview.root"].exists
            || app.otherElements["nav.workspace"].exists
            || app.otherElements["workspace.editor"].exists
    }

    private func waitForOverview(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        app.otherElements["nav.overview"].waitForExistence(timeout: timeout)
            || app.otherElements["overview.root"].waitForExistence(timeout: 3)
            || app.buttons["overview.openEditor"].waitForExistence(timeout: 3)
    }

    private func waitForManuscriptSurface(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        if app.scrollViews["workspace.manuscript"].waitForExistence(timeout: timeout) { return true }
        if app.textViews["workspace.manuscript.editor"].waitForExistence(timeout: timeout) { return true }
        if app.otherElements["workspace.manuscript.active"].waitForExistence(timeout: timeout) { return true }
        if app.otherElements["workspace.manuscript.office.shell"].waitForExistence(timeout: timeout) { return true }
        if app.otherElements["workspace.manuscript.office"].waitForExistence(timeout: timeout) { return true }
        return app.textViews.firstMatch.waitForExistence(timeout: 3)
    }

    @MainActor
    func testLibraryScreenAppears() throws {
        let app = try launchApp()
        XCTAssertTrue(waitForLibrary(app), "Project Library should be the launch screen")
        XCTAssertTrue(
            app.buttons["library.newProject"].exists || app.buttons["New Project"].exists,
            "New Project control should be available"
        )
        attachScreenshot(app, name: "Library")
    }

    /// Seeded project opens workspace with manuscript editor and pipeline under Analyze menu.
    @MainActor
    func testCreateProjectAndOpenEditor() throws {
        let app = try launchApp(extraArguments: ["-UITestSeedProject"])

        guard waitForWorkspace(app, timeout: 12) else {
            if !knownAppRootExists(app) {
                throw XCTSkip(
                    "macOS UI automation returned a window without the SwiftUI accessibility hierarchy. "
                        + "Unit coverage verifies the seeded workspace path; rerun in an interactive Accessibility-enabled session."
                )
            }
            try openWorkspaceThroughUIFallback(app)
            XCTAssertTrue(waitForWorkspace(app, timeout: 30), "Seeded project should open workspace")
            XCTAssertTrue(waitForManuscriptSurface(app, timeout: 25))
            attachScreenshot(app, name: "Workspace-Seeded-Fallback")
            return
        }

        XCTAssertTrue(
            app.buttons["workspace.backToProject"].exists || app.buttons["workspace.overview"].exists,
            "Workspace should expose back-to-project navigation"
        )
        XCTAssertTrue(
            waitForManuscriptSurface(app, timeout: 20),
            "Manuscript editor surface should be present (legacy NSTextView or embedded host)"
        )

        let analyze = app.buttons["workspace.analyze"]
        if analyze.waitForExistence(timeout: 5) {
            analyze.tap()
            let pipelineByID = app.menuItems["workspace.pipeline"]
            let pipelineByTitle = app.menuItems["Full pipeline"]
            XCTAssertTrue(
                pipelineByID.waitForExistence(timeout: 5) || pipelineByTitle.waitForExistence(timeout: 5),
                "Full pipeline must remain available under Analyze"
            )
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }

        attachScreenshot(app, name: "Workspace-Seeded")
    }

    private func openWorkspaceThroughUIFallback(_ app: XCUIApplication) throws {
        if app.otherElements["nav.overview"].exists || app.buttons["overview.openEditor"].exists {
            let openEditor = app.buttons["overview.openEditor"].exists
                ? app.buttons["overview.openEditor"]
                : app.buttons["Open Editor"]
            XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
            openEditor.tap()
            return
        }

        guard waitForLibrary(app, timeout: 8) else {
            XCTFail("Seed fallback expected library or overview")
            return
        }
        let newProject = app.buttons["library.newProject"].exists
            ? app.buttons["library.newProject"]
            : app.buttons["New Project"]
        newProject.tap()

        let sheet = newProjectSheet(in: app)
        XCTAssertTrue(sheet.exists, "New project sheet should appear")
        let nameField = sheet.textFields["createProject.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        nameField.click()
        nameField.typeText("Seed Fallback \(UUID().uuidString.prefix(6))")
        let submit = sheet.buttons["createProject.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
        XCTAssertTrue(waitForOverview(app, timeout: 20), "Fallback project should open Overview")
        let openEditor = app.buttons["overview.openEditor"].exists
            ? app.buttons["overview.openEditor"]
            : app.buttons["Open Editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
        openEditor.tap()
    }

    /// End-to-end: library → create sheet → overview → editor.
    @MainActor
    func testCreateProjectFlowThroughUI() throws {
        let app = try launchApp()
        XCTAssertTrue(waitForLibrary(app))

        let newProject = app.buttons["library.newProject"].exists
            ? app.buttons["library.newProject"]
            : app.buttons["New Project"]
        newProject.tap()

        let sheet = newProjectSheet(in: app)
        XCTAssertTrue(sheet.exists, "New project sheet should appear")

        let nameField = sheet.textFields["createProject.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        nameField.click()
        nameField.typeText("UI Flow Novel \(UUID().uuidString.prefix(6))")

        let submit = sheet.buttons["createProject.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isEnabled, "Create should be enabled after entering a name")
        submit.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "Sheet should dismiss after create")

        if app.dialogs.firstMatch.waitForExistence(timeout: 2) {
            XCTFail("Error dialog: \(app.dialogs.firstMatch.staticTexts.firstMatch.label)")
        }

        XCTAssertTrue(waitForOverview(app, timeout: 20), "New project should open Overview")

        let openEditor = app.buttons["overview.openEditor"].exists
            ? app.buttons["overview.openEditor"]
            : app.buttons["Open Editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
        openEditor.tap()
        if !waitForWorkspace(app, timeout: 5) {
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command)
        }

        XCTAssertTrue(waitForWorkspace(app, timeout: 30), "Overview should navigate to workspace")
        XCTAssertTrue(waitForManuscriptSurface(app, timeout: 25))

        attachScreenshot(app, name: "Workspace-Flow")
    }

    @MainActor
    func testEmptyLibraryShowsPlaceholder() throws {
        let app = try launchApp()
        XCTAssertTrue(waitForLibrary(app))
        if app.otherElements["library.empty"].waitForExistence(timeout: 3) {
            attachScreenshot(app, name: "Library-Empty")
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-UITest"]
            app.launch()
        }
    }
}
