import XCTest

/// Drives the app through its screens in the simulator and keeps a screenshot
/// of each one.
///
/// This is the only way anyone can look at DosiCrew without a Mac or a signed
/// build on a device: the app is developed in an environment that cannot run
/// it. The pictures are committed to `Screenshots/` by the workflow, so layout
/// problems surface here rather than on somebody's iPhone at seven in the
/// morning.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments = [
            // In-memory store with the demo plan; never touches real data.
            "-DosiCrewUITestSeed",
            // iOS folds `-key value` launch arguments into UserDefaults, which
            // is how the "who is using this iPhone" prompt is answered before
            // it can cover the first screenshot.
            "-personName", "Papa",
            // German: the language this app is actually used in.
            "-AppleLanguages", "(de)",
            "-AppleLocale", "de_DE",
        ]
        app.launch()
    }

    func testCaptureEveryScreen() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "The app never reached its tab bar")

        // Tabs are selected by position rather than by label, so the run does
        // not break when a translation changes.
        capture("01-Heute")

        scrollDown()
        capture("02-Heute-unten")

        selectTab(1)
        capture("03-Medikamente")

        openMedication(named: "Amoxicillin")
        capture("04-Medikament-bearbeiten")
        dismissSheet()

        selectTab(2)
        capture("05-Ereignisse")

        selectTab(3)
        capture("06-Einstellungen")

        // Assertions last, so a failure never costs us the pictures.
        selectTab(0)
        // The tab kept the scroll position from `scrollDown()`, and the
        // duplicate banner sits at the very top — out of the hierarchy, not
        // just off-screen.
        scrollToTop()
        XCTAssertTrue(
            app.staticTexts["Amoxicillin"].waitForExistence(timeout: 5),
            "The seeded medication is missing from the Today screen"
        )
        XCTAssertTrue(
            app.staticTexts["Doppelt gegeben"].waitForExistence(timeout: 5),
            "The duplicate-dose warning did not appear, or German localisation did not load"
        )
    }

    // MARK: - Steps

    private func selectTab(_ index: Int) {
        let tabs = app.tabBars.firstMatch.buttons
        guard tabs.count > index else {
            XCTFail("Expected at least \(index + 1) tabs, found \(tabs.count)")
            return
        }
        tabs.element(boundBy: index).tap()
    }

    /// Opens a medication by name rather than by position.
    ///
    /// "The first cell" stopped meaning the first medication once the list grew
    /// section headers per child: the tap landed on the header and the editor
    /// never opened, which cost a screenshot without failing the test.
    private func openMedication(named name: String) {
        let isRow = NSPredicate(format: "label BEGINSWITH %@", name)
        for query in [app.buttons, app.cells] {
            let row = query.matching(isRow).firstMatch
            if row.waitForExistence(timeout: 5) {
                row.tap()
                return
            }
        }
        // The row may expose its parts rather than one folded label.
        let text = app.staticTexts[name]
        if text.waitForExistence(timeout: 2) {
            text.tap()
            return
        }
        XCTFail("No medication row labelled \(name)")
    }

    private func dismissSheet() {
        // The medication editor is modal and blocks the tab bar.
        let cancel = app.buttons["Abbrechen"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
    }

    private func scrollDown() {
        guard let scrollable = scrollable() else { return }
        scrollable.swipeUp()
    }

    /// Three swipes: the day list is as long as the number of children makes
    /// it, and one swipe no longer reaches the top.
    private func scrollToTop() {
        guard let scrollable = scrollable() else { return }
        for _ in 0..<3 { scrollable.swipeDown() }
    }

    private func scrollable() -> XCUIElement? {
        if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
        if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
        return nil
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
