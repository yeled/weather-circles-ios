import XCTest

/// Drives the real UI to produce the App Store screenshot set.
///
/// The point of doing this as a UI test rather than `simctl io screenshot`
/// is that a test can actually *tap*: earlier screenshot runs had to add
/// temporary launch-argument hooks to `ContentView` to force a sheet open,
/// because `simctl` can't touch the screen. Everything here is a real
/// gesture on the shipping UI, so the app carries no screenshot-only code.
///
/// Only deterministic targets are used. Tapping "the wind barb" would be a
/// lottery — the barb points wherever the weather says — so the explainer
/// shot taps the *centre* of the plot, which is always the cloud circle.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
        grantLocationIfAsked()
        waitForFirstFetch()
    }

    func testCaptureAppStoreScreenshots() throws {
        // 1 — the station plot. Taken first, while the one-time "tap any
        // part of the circle" nudge is still on screen (it retires itself
        // the moment the guide is opened, which happens further down).
        snapshot("1Main")

        // 2 — the seven-day page, one paging swipe up.
        swipeToNextPage()
        snapshot("2Forecast")

        // 3 — the area chart, one more swipe up. Its circles are fetched
        // only once the page is on screen, so wait for them to land.
        swipeToNextPage()
        XCTAssertTrue(chartCaption.waitForExistence(timeout: 30),
                      "The area chart should plot its places once paged to")
        waitUntilStill(chartCaption)
        snapshot("3Chart")
        swipeToPreviousPage()
        swipeToPreviousPage()

        // 4 — an explainer sheet. Centre of the plot = the cloud circle,
        // the one slot that's on every circle regardless of weather.
        plot.tap()
        XCTAssertTrue(app.staticTexts["Cloud cover"].waitForExistence(timeout: 5),
                      "Tapping the circle should open the cloud-cover explainer")
        snapshot("4Explainer")
        dismissSheet()

        // 5 — the full guide, from the footer button.
        app.buttons["What am I looking at?"].tap()
        XCTAssertTrue(app.staticTexts["Reading the circle"].waitForExistence(timeout: 5),
                      "The footer button should open the guide")
        snapshot("5Guide")
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private var plot: XCUIElement { app.otherElements["stationPlot"].firstMatch }

    /// The area chart's "N places, now" line — only present once the
    /// circles have actually come back.
    private var chartCaption: XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH ' places, now'")).firstMatch
    }

    /// The permission alert belongs to SpringBoard, not the app.
    private func grantLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// The header caption reads "Loading…" until the first fetch lands;
    /// screenshotting before that catches a 25%-opacity placeholder plot.
    private func waitForFirstFetch() {
        let updated = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Updated'")).firstMatch
        _ = updated.waitForExistence(timeout: 30)
    }

    private func swipeToNextPage() {
        drag(fromY: 0.75, toY: 0.2)
    }

    private func swipeToPreviousPage() {
        // Starting low avoids the top of the page, where the same downward
        // drag is pull-to-refresh rather than paging.
        drag(fromY: 0.45, toY: 0.9)
    }

    private func drag(fromY: Double, toY: Double) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end)
        waitUntilStill(app.staticTexts["Next 7 days"])
    }

    private func dismissSheet() {
        // Swipe the sheet back down by its grabber rather than hunting for
        // a close button — the explainer sheet has none.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
        top.press(forDuration: 0.05, thenDragTo: bottom)
        waitUntilStill(plot)
    }

    /// A paged `ScrollView` snaps *after* the drag ends, and screenshotting
    /// mid-snap catches the previous page bleeding in at the top. Waiting a
    /// fixed second is a guess; waiting for the element to stop moving is
    /// the actual condition.
    private func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 6) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = element.exists ? element.frame : .zero
        var stillFor = 0
        while Date() < deadline {
            usleep(200_000)
            let now = element.exists ? element.frame : .zero
            stillFor = (now == last) ? stillFor + 1 : 0
            last = now
            if stillFor >= 2 { return }            // ~400 ms unchanged
        }
    }
}
