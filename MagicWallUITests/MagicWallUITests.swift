import XCTest

/// End-to-end UI tests. They drive the real app: sidebar navigation, the
/// fullscreen preview (including the regression where the preview must cover
/// the sidebar), and the Settings window with its Theme editor.
///
/// macOS notes:
/// - `XCUIElement.click()` is used instead of `tap()`: on macOS `tap()` does
///   not reliably deliver a usable click to SwiftUI controls.
/// - The tests assume the library has at least one video (development fixtures
///   are imported with `mwctl import`). If the library is empty, the preview
///   tests are skipped instead of failing.
final class MagicWallUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Force English so label-based assertions are deterministic.
        app.launchArguments += ["-appLanguage", "en"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20), "Main window should appear")
        app.windows.firstMatch.click()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    // MARK: - Helpers

    /// SwiftUI containers surface under different element kinds (`button`,
    /// `group`, `other`, …) depending on their content, so identifiers are
    /// matched across every descendant kind.
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func anyElement(matching identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func sidebarItem(_ id: String) -> XCUIElement {
        app.buttons["sidebar.item.\(id)"]
    }

    private func firstVideoCard() -> XCUIElement? {
        let card = anyElement(matching: "grid.videoCard")
        return card.waitForExistence(timeout: 10) ? card : nil
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func firstElement(withLabel label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", label)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    // MARK: - Tests

    func testSidebarIsComplete() {
        for id in ["home", "explore", "library", "favorites"] {
            XCTAssertTrue(sidebarItem(id).waitForExistence(timeout: 5), "Missing sidebar item '\(id)'")
        }
        XCTAssertTrue(app.buttons["sidebar.import"].exists, "Import button should exist")
        XCTAssertTrue(app.buttons["sidebar.settings"].exists, "Settings entry should exist")
    }

    func testTabNavigationSwitchesContent() {
        XCTAssertTrue(
            anyElement("home.hero").waitForExistence(timeout: 10),
            "Home hero should be visible on launch"
        )

        sidebarItem("explore").click()
        XCTAssertTrue(
            anyElement("explore.chips").waitForExistence(timeout: 5),
            "Explore category chips should be visible"
        )

        sidebarItem("library").click()
        XCTAssertTrue(
            anyElement("library.header").waitForExistence(timeout: 5),
            "Library header should be visible"
        )

        sidebarItem("home").click()
        XCTAssertTrue(
            anyElement("home.hero").waitForExistence(timeout: 5),
            "Home hero should be visible again after navigating back"
        )
    }

    /// Regression: previously the preview was layered inside the detail area
    /// only, so the sidebar stayed clickable and the video appeared "stuck".
    /// Now a click over the sidebar area can only hit the preview backdrop:
    /// it closes the preview instead of navigating underneath it.
    func testPreviewBlocksNavigationUnderneath() throws {
        guard let card = firstVideoCard() else {
            throw XCTSkip("Library is empty — import fixtures with mwctl first")
        }
        card.click()

        let overlay = anyElement("preview.overlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 8), "Preview overlay should appear")
        XCTAssertTrue(anyElement("home.hero").exists, "Home should be the tab underneath")

        // Click exactly where the sidebar "Library" item is; coordinate clicks
        // work regardless of accessibility hit-testing through the overlay.
        sidebarItem("library")
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click()

        // The click was consumed by the preview (backdrop close), so no
        // navigation happened underneath: still on Home, never on Library.
        XCTAssertFalse(anyElement("library.header").waitForExistence(timeout: 2), "Must not navigate under the preview")
        XCTAssertTrue(waitForDisappearance(of: overlay, timeout: 5), "Backdrop click should close the preview")
        XCTAssertTrue(anyElement("home.hero").waitForExistence(timeout: 5), "Still on Home after closing")
    }

    func testPreviewCloseButtonWorks() throws {
        guard let card = firstVideoCard() else {
            throw XCTSkip("Library is empty — import fixtures with mwctl first")
        }
        card.click()

        let overlay = anyElement("preview.overlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 8))

        let close = anyElement("preview.close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Close button should exist")
        close.click()
        XCTAssertTrue(waitForDisappearance(of: overlay, timeout: 5), "Preview should close from its X button")
    }

    func testSettingsWindowShowsThemeEditor() {
        app.buttons["sidebar.settings"].click()

        let themeTab = firstElement(withLabel: "Theme")
        XCTAssertTrue(themeTab.waitForExistence(timeout: 15), "Settings should open with a Theme tab")
        if themeTab.isHittable {
            themeTab.click()
        }

        XCTAssertTrue(
            anyElement("theme.editor").waitForExistence(timeout: 10),
            "Theme editor should be reachable"
        )

        app.typeKey("w", modifierFlags: .command)
    }
}
