import AppKit
import XCTest

/// End-to-end UI tests. They drive the real app: sidebar navigation, the
/// fullscreen preview (including the regression where the preview must cover
/// the sidebar), video renaming, the empty-library experience, and Settings.
///
/// macOS notes:
/// - `XCUIElement.click()` is used instead of `tap()`: on macOS `tap()` does
///   not reliably deliver a usable click to SwiftUI controls.
/// - `Scripts/e2e.sh` seeds an isolated library and points the scheme's
///   `MW_E2E_SEEDED_DATA_DIR` at it; tests never touch the real user library
///   when launched that way. Without a valid directory the tests fall back to
///   the real library and skip video-dependent cases when it is empty.
final class MagicWallUITests: XCTestCase {
    private var app: XCUIApplication!
    private var ownedDataDirectory: URL?
    private var currentDataDirectory: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Scripts/e2e.sh prepares the seeded library and points the scheme's
        // MW_E2E_SEEDED_DATA_DIR at it (the shell environment is not forwarded
        // to the test runner). Without a valid directory the tests fall back
        // to the real library and skip video-dependent cases when it is empty.
        let seeded = ProcessInfo.processInfo.environment["MW_E2E_SEEDED_DATA_DIR"]
        let hasSeededLibrary = seeded?.isEmpty == false
            && FileManager.default.fileExists(atPath: seeded ?? "")
        launchApp(dataDirectory: hasSeededLibrary ? seeded : nil)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let ownedDataDirectory {
            try? FileManager.default.removeItem(at: ownedDataDirectory)
        }
    }

    // MARK: - Helpers

    /// SwiftUI containers surface under different element kinds (`button`,
    /// `group`, `other`, …) depending on their content, so identifiers are
    /// matched across every descendant kind.
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func anyElement(matching identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        _ = element.waitForExistence(timeout: timeout)
        return element
    }

    private func sidebarItem(_ id: String) -> XCUIElement {
        app.buttons["sidebar.item.\(id)"]
    }

    private func firstVideoCard() -> XCUIElement? {
        let card = anyElement(matching: "grid.videoCard", timeout: 15)
        return card.exists ? card : nil
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func makeEmptyDataDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MagicWallUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func launchApp(dataDirectory: String?, owned: Bool = false) {
        app?.terminate()

        if owned, let existing = ownedDataDirectory {
            try? FileManager.default.removeItem(at: existing)
            ownedDataDirectory = nil
        }

        terminateRunningInstances()

        app = XCUIApplication()
        // Force English so label-based assertions are deterministic.
        app.launchArguments += ["-appLanguage", "en"]
        if let dataDirectory {
            app.launchEnvironment["MAGICWALL_DATA_DIR"] = dataDirectory
            currentDataDirectory = dataDirectory
        }
        if owned, let dataDirectory {
            ownedDataDirectory = URL(fileURLWithPath: dataDirectory, isDirectory: true)
        }

        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20), "Main window should appear")
        app.windows.firstMatch.click()
    }

    /// Quits every MagicWall instance the test does not own before launching.
    ///
    /// An app already running outside the test — the developer's own copy, a
    /// launch at login, or a leftover from a previous test that closed its
    /// window — answers the launch instead of the process under test. The fresh
    /// process then never gets a window and every assertion fails with "Main
    /// window should appear". Terminating by bundle identifier first makes the
    /// launch deterministic; the library lives in the database, so nothing is
    /// lost by quitting.
    private func terminateRunningInstances() {
        let bundleID = "app.magicwall"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return }

        for instance in running {
            instance.terminate()
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline,
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            usleep(100_000)
        }

        for instance in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            instance.forceTerminate()
        }
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
            anyElement("home.hero").waitForExistence(timeout: 10)
                || anyElement("empty.library.title").waitForExistence(timeout: 10),
            "Home should show either the hero or the empty state"
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
            anyElement("home.hero").waitForExistence(timeout: 5)
                || anyElement("empty.library.title").waitForExistence(timeout: 5),
            "Home should be visible again after navigating back"
        )
    }

    /// The empty library is a first-class state: every tab must explain how to
    /// add videos and offer the import action without requiring a fixture.
    func testEmptyLibraryShowsEmptyState() throws {
        let directory = try makeEmptyDataDirectory()
        launchApp(dataDirectory: directory.path, owned: true)

        XCTAssertTrue(
            anyElement("empty.library.title").waitForExistence(timeout: 15),
            "Empty library title should be visible on Home"
        )
        XCTAssertTrue(anyElement("empty.import").exists, "Empty state should offer the import action")
        XCTAssertFalse(anyElement("grid.videoCard").exists, "No video cards should exist in an empty library")

        for id in ["explore", "library", "favorites", "home"] {
            sidebarItem(id).click()
            XCTAssertTrue(
                anyElement("empty.library.title").waitForExistence(timeout: 5),
                "Tab '\(id)' should show the empty-library state"
            )
            XCTAssertFalse(anyElement("grid.videoCard").exists, "Tab '\(id)' should not show video cards")
        }
    }

    /// Regression: previously the preview was layered inside the detail area
    /// only, so the sidebar stayed clickable and the video appeared "stuck".
    /// Now a click over the sidebar area can only hit the preview backdrop:
    /// it closes the preview instead of navigating underneath it.
    func testPreviewBlocksNavigationUnderneath() throws {
        guard let card = firstVideoCard() else {
            throw XCTSkip("Library is empty — run via Scripts/e2e.sh or import fixtures with mwctl first")
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
            throw XCTSkip("Library is empty — run via Scripts/e2e.sh or import fixtures with mwctl first")
        }
        card.click()

        let overlay = anyElement("preview.overlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 8))

        let close = anyElement("preview.close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Close button should exist")
        close.click()
        XCTAssertTrue(waitForDisappearance(of: overlay, timeout: 5), "Preview should close from its X button")
    }

    /// The rotation bar lives with the favorites: it appears when there is at
    /// least one favorite, and the countdown caption follows the switch.
    /// Enabling the rotation applies a seeded wallpaper for the duration of
    /// the test (the app is terminated right after).
    func testFavoritesRotationBarTogglesCountdown() throws {
        sidebarItem("favorites").click()

        let toggle = anyElement(matching: "favorites.rotation.toggle")
        guard toggle.exists else {
            throw XCTSkip("No favorites in the library — run via Scripts/e2e.sh or favorite a video with mwctl first")
        }

        XCTAssertFalse(
            anyElement("favorites.rotation.caption").exists,
            "The countdown caption should be hidden while the rotation is off"
        )

        toggle.click()

        XCTAssertTrue(
            anyElement("favorites.rotation.caption").waitForExistence(timeout: 5),
            "Enabling the rotation should show the countdown caption"
        )
        XCTAssertTrue(anyElement("favorites.rotation.interval").exists, "The interval menu should be available")
        XCTAssertTrue(anyElement("favorites.rotation.next").exists, "The next-now button should be available")

        toggle.click()

        XCTAssertTrue(
            waitForDisappearance(of: anyElement("favorites.rotation.caption"), timeout: 5),
            "Disabling the rotation should hide the countdown caption again"
        )
    }

    /// Renames a video from the fullscreen preview and verifies the change is
    /// reflected immediately and persisted across an app relaunch.
    func testRenameVideoFromPreview() throws {
        guard let card = firstVideoCard() else {
            throw XCTSkip("Library is empty — run via Scripts/e2e.sh or import fixtures with mwctl first")
        }
        card.click()

        let overlay = anyElement("preview.overlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 8), "Preview overlay should appear")

        let renameButton = anyElement("preview.rename")
        XCTAssertTrue(renameButton.waitForExistence(timeout: 5), "Rename button should exist")
        renameButton.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Rename alert should appear")

        let field = sheet.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Rename field should appear")
        field.click()
        field.typeKey("a", modifierFlags: .command)

        let newTitle = "Renamed \(UUID().uuidString.prefix(6))"
        field.typeText(newTitle)

        let save = sheet.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save button should appear")
        save.click()

        let previewTitle = anyElement("preview.title")
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5), "Preview title should exist")
        XCTAssertTrue(app.staticTexts[newTitle].waitForExistence(timeout: 5), "Preview title should update immediately")

        anyElement("preview.close").click()
        XCTAssertTrue(waitForDisappearance(of: overlay, timeout: 5))
        XCTAssertTrue(app.staticTexts[newTitle].waitForExistence(timeout: 5), "Card title should update")

        // Relaunch against the same data directory and check persistence.
        app.terminate()
        launchApp(dataDirectory: currentDataDirectory)
        XCTAssertTrue(
            app.staticTexts[newTitle].waitForExistence(timeout: 15),
            "Renamed title should survive an app relaunch"
        )
    }

    /// Regression: the app keeps running after the window is closed (the
    /// wallpaper engine must not stop), but activating it again has to bring
    /// the library window back instead of leaving the app with no UI.
    func testWindowReopensAfterClose() {
        let window = app.windows["MagicWall"]
        XCTAssertTrue(window.waitForExistence(timeout: 20), "Main window should exist")

        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitForDisappearance(of: window, timeout: 10), "Main window should close")

        // Same path Finder/Dock use: open the already running app, which asks
        // the delegate to handle the reopen. Match the app under test by path,
        // not just by bundle id, so stray copies cannot satisfy the open.
        let expectedURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("MagicWall.app")
        let runningApp = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "app.magicwall"
                && $0.bundleURL?.standardizedFileURL == expectedURL.standardizedFileURL
        } ?? NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "app.magicwall" }
        guard let url = runningApp?.bundleURL else {
            return XCTFail("Could not resolve the app bundle URL")
        }
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )

        XCTAssertTrue(
            app.windows["MagicWall"].waitForExistence(timeout: 15),
            "Activating the app should restore the closed library window"
        )
    }

    func testSettingsWindowShowsThemeEditor() {
        app.buttons["sidebar.settings"].click()

        let themeTab = anyElement("settings.nav.theme")
        XCTAssertTrue(themeTab.waitForExistence(timeout: 15), "Settings should open with a Theme tab")
        themeTab.click()

        XCTAssertTrue(
            anyElement("theme.editor").waitForExistence(timeout: 10),
            "Theme editor should be reachable"
        )

        app.typeKey("w", modifierFlags: .command)
    }

    /// The lock screen belongs to the system's wallpaper pipeline, so the app
    /// can only report the state and hand over the Settings pane: check that
    /// entry point is reachable from General. The state itself depends on the
    /// machine running the tests, so only the presence is asserted.
    func testSettingsShowsLockScreenCard() throws {
        // The card only exists on the systems the extension supports, so the
        // guard is the OS version — never the element, which would let a
        // regression pass as a skip.
        let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(macOS26) else {
            throw XCTSkip("The lock screen card requires macOS 26 or later")
        }

        app.buttons["sidebar.settings"].click()

        let generalTab = anyElement("settings.nav.general")
        XCTAssertTrue(generalTab.waitForExistence(timeout: 15), "Settings should open with a General tab")
        generalTab.click()

        XCTAssertTrue(
            anyElement(matching: "settings.lockscreen.openSettings").exists,
            "The card should offer the System Settings shortcut"
        )
        XCTAssertTrue(
            app.staticTexts["Lock screen"].exists,
            "The card should be titled"
        )

        app.typeKey("w", modifierFlags: .command)
    }
}
