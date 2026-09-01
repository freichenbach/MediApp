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

        openFirstRow()
        capture("04-Medikament-bearbeiten")
        dismissSheet()

        selectTab(2)
        capture("05-Ereignisse")

        selectTab(3)
        capture("06-Einstellungen")

        // Assertions last, so a failure never costs us the pictures.
        selectTab(0)
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

    private func openFirstRow() {
        let row = app.cells.firstMatch
        guard row.waitForExistence(timeout: 5) else { return }
        row.tap()
    }

    private func dismissSheet() {
        // The medication editor is modal and blocks the tab bar.
        let cancel = app.buttons["Abbrechen"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
    }

    private func scrollDown() {
        let scrollable = app.scrollViews.firstMatch.exists
            ? app.scrollViews.firstMatch
            : app.collectionViews.firstMatch
        guard scrollable.exists else { return }
        scrollable.swipeUp()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
