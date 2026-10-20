import XCTest

final class VacuulaUITests: XCTestCase {
    func testVisibleDemoNavigatesMainScreensAndExits() throws {
        let app = XCUIApplication()
        // Show the actual connection UI without discovering or contacting a server.
        app.launchArguments = ["--demo-entry"]
        app.launch()
        XCTAssertTrue(app.buttons["try-demo"].waitForExistence(timeout: 10))
        app.buttons["try-demo"].tap()
        XCTAssertTrue(app.buttons["exit-demo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start cleaning"].isEnabled)
        app.buttons["activity-button"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scheduled clean couldn’t start"].exists)
        app.buttons["Done"].tap()
        app.tabBars.buttons["Rooms"].tap()
        app.buttons["floor.preview-map"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["floor-map-image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Preview room"].exists)
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.buttons["add-schedule"].waitForExistence(timeout: 5))
        app.buttons["add-schedule"].tap()
        XCTAssertTrue(app.navigationBars["New schedule"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        let run = app.buttons["cleaning-record-preview-done"]
        if !run.isHittable { app.swipeUp() }
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        XCTAssertTrue(app.navigationBars["Clean details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["run-area-comparison"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["map-rotation-picker"].waitForExistence(timeout: 5))
        capture("Visible demo — Settings")
        app.buttons["exit-demo"].tap()
        XCTAssertTrue(app.buttons["try-demo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Robot"].exists)
        // A second visit starts a fresh sample session.
        app.buttons["try-demo"].tap()
        XCTAssertTrue(app.buttons["exit-demo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start cleaning"].isEnabled)
    }

    func testGlobalMapRotationKeepsMapAndOverlaysVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-map"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Rooms"].tap()
        app.buttons["floor.preview-map"].tap()
        let map = app.descendants(matching: .any).matching(identifier: "floor-map-image").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        capture("Map Rotation 0")
        for degrees in [90, 180, 270] {
            app.tabBars.buttons["Settings"].tap()
            let picker = app.buttons["map-rotation-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.tap()
            app.buttons["\(degrees)° clockwise"].tap()
            app.tabBars.buttons["Rooms"].tap()
            let expected = "\(degrees)° clockwise"
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: map)], timeout: 5) == .completed)
            XCTAssertTrue(map.isHittable)
            capture("Map Rotation \(degrees)")
        }
    }

    func testHomeAndScheduleShowRunSourcesAndStats() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Robot"].waitForExistence(timeout: 10))
        let recent = app.buttons["home-recent-preview-cancelled"]
        for _ in 0..<3 { if recent.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertTrue(recent.label.contains("Schedule"))
        XCTAssertTrue(recent.label.contains("sq ft"))
        XCTAssertTrue(recent.label.contains("min"))
        capture("Home Recent Cleans")
        app.tabBars.buttons["Schedule"].tap()
        let scheduled = app.buttons["scheduled-recent-preview-cancelled"]
        for _ in 0..<3 { if scheduled.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scheduled-recent-preview-done"].exists)
        capture("Scheduled Runs")
        scheduled.tap()
        XCTAssertTrue(app.navigationBars["Clean details"].waitForExistence(timeout: 5))
    }

    func testDirtBinErrorExplainsAttentionBeforeControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-bin-missing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Dirt bin missing"].waitForExistence(timeout: 10))
        let detail = app.staticTexts["robot-issue-detail"]
        XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("Put the dirt bin back in"))
        XCTAssertLessThan(detail.frame.maxY, app.buttons["Stop cleaning"].frame.minY)
        XCTAssertFalse(app.buttons["Start cleaning"].isEnabled)
        capture("Dirt Bin Error")
    }

    func testScheduleLoadingAndFailureDisableCreation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-schedule-loading"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Schedule"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Loading schedule…"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["add-schedule"].isEnabled)
        capture("Schedule Loading Disabled")
        app.terminate()
        app.launchArguments = ["--demo", "--demo-schedule-error"]
        app.launch()
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Schedule unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["add-schedule"].isEnabled)
        XCTAssertTrue(app.buttons["Try again"].exists)
        capture("Schedule Error Disabled")
    }
    func testHistoryStatsAndAutomaticMapAreaComparison() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["History"].waitForExistence(timeout: 10))
        app.tabBars.buttons["History"].tap()
        let complete = app.buttons["cleaning-record-preview-done"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Cancelled · Schedule"].exists)
        capture("Cleaning History")
        XCTAssertFalse(app.buttons["expected-area-button"].exists)
        complete.tap()
        XCTAssertTrue(app.navigationBars["Clean details"].waitForExistence(timeout: 5))
        let area = app.descendants(matching: .any).matching(identifier: "run-cleaned-area").firstMatch
        let comparison = app.descendants(matching: .any).matching(identifier: "run-area-comparison").firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        XCTAssertTrue(area.label.contains("237 sq ft"))
        XCTAssertTrue(comparison.label.contains("92%"))
        capture("Cleaning History Stats")
    }

    func testScheduleCreationEditingAndDeletionInPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-empty-schedules"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Schedule"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.buttons["add-schedule"].waitForExistence(timeout: 10))
        app.buttons["add-schedule"].tap()
        XCTAssertTrue(app.navigationBars["New schedule"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-schedule"].isEnabled)
        let monday = app.buttons["schedule-day-mon"]
        monday.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: monday)], timeout: 5) == .completed)
        XCTAssertTrue(app.buttons["save-schedule"].isEnabled)
        app.buttons["save-schedule"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        capture("Schedule Created")
        app.buttons["Edit"].tap()
        app.buttons["schedule-day-tue"].tap()
        app.buttons["save-schedule"].tap()
        XCTAssertTrue(app.staticTexts["Mon, Tue"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        app.buttons["Delete schedule"].tap()
        XCTAssertTrue(app.staticTexts["No scheduled cleans"].waitForExistence(timeout: 5))
    }

    func testLiveDiscoveryStatusAndMapReadOnly() throws {
        guard ProcessInfo.processInfo.environment["VACUULA_LIVE_TESTS"] == "1" else { throw XCTSkip("Set VACUULA_LIVE_TESTS=1 to run an explicit read-only LAN check.") }
        let app = XCUIApplication()
        app.launchArguments = ["--read-only"]
        addUIInterruptionMonitor(withDescription: "Local network permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 5), permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
        if app.buttons["Try again"].waitForExistence(timeout: 2) { app.buttons["Try again"].tap() }
        XCTAssertTrue(app.tabBars.buttons["Robot"].waitForExistence(timeout: 30), "The app should discover and connect without address entry.")
        XCTAssertTrue(app.staticTexts["Read-only preview. Robot controls are disabled."].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "battery")).firstMatch.waitForExistence(timeout: 45))
        capture("Live Robot")
        app.tabBars.buttons["Rooms"].tap()
        let floor = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "floor.")).firstMatch
        XCTAssertTrue(floor.waitForExistence(timeout: 10))
        floor.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "floor-map-image").firstMatch.waitForExistence(timeout: 30))
        capture("Live Floor Map")
    }
    func testPreviewNavigationAndDisabledControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Charging"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start cleaning"].isEnabled)
        capture("Robot")
        app.tabBars.buttons["Rooms"].tap()
        XCTAssertTrue(app.buttons["floor.preview-map"].exists)
        capture("Rooms")
        app.tabBars.buttons["Settings"].tap()
        let serverName = app.descendants(matching: .any).matching(identifier: "server-name").firstMatch
        XCTAssertTrue(serverName.exists)
        XCTAssertTrue(serverName.label.contains("Vacuula Server") || (serverName.value as? String)?.contains("Vacuula Server") == true)
        capture("Settings")
    }
    func testLargeTextAndDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--dark-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Charging"].waitForExistence(timeout: 10))
        capture("Robot — Large Text and Dark Mode")
        app.swipeUp()
        XCTAssertTrue(app.buttons["Start cleaning"].exists)
    }
    func testHomeFitsWithoutScrolling() throws {
        for cleaning in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = cleaning ? ["--demo", "--demo-cleaning"] : ["--demo"]
            app.launch()
            let options = app.switches["gentle-navigation"]
            XCTAssertTrue(options.waitForExistence(timeout: 10))
            XCTAssertTrue(options.isHittable, "Cleaning options should be visible without scrolling.")
            XCTAssertLessThanOrEqual(options.frame.maxY, app.tabBars.firstMatch.frame.minY,
                                     "The last option must clear the floating tab bar.")
            if cleaning {
                XCTAssertTrue(app.buttons["Pause cleaning"].exists)
                XCTAssertTrue(app.buttons["Return to base"].exists)
            }
            capture(cleaning ? "Home — Cleaning" : "Home — Docked")
            app.terminate()
        }
    }
    func testCleaningButtonAppearance() throws {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--button-preview"] + (dark ? ["--dark-preview"] : [])
            app.launch()
            let buttons = app.buttons.matching(identifier: "Start cleaning")
            XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(buttons.count, 2)
            XCTAssertTrue(buttons.element(boundBy: 0).isEnabled)
            XCTAssertFalse(buttons.element(boundBy: 1).isEnabled)
            capture(dark ? "Cleaning button — Dark" : "Cleaning button — Light")
            app.terminate()
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testActivitySummaryAndReadMarkersResetBetweenDemoSessions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-activity", "--reset-activity-read"]
        app.launch()
        let bell = app.buttons["activity-button"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.label, "Activity, 3 unread")
        XCTAssertFalse(app.buttons["activity-banner"].exists, "Recovered history must not replay foreground banners.")
        bell.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scheduled clean couldn’t start"].exists)
        XCTAssertTrue(app.staticTexts["The robot couldn’t reach Kitchen. Check that the route is clear."].exists)
        capture("Activity summary")
        XCTAssertTrue(app.staticTexts["3 events · 3 unread"].exists, "Opening history must not mark unseen events read.")
        app.descendants(matching: .any)["activity-event-3"].tap()
        XCTAssertTrue(app.staticTexts["3 events · 2 unread"].exists)
        app.buttons["mark-all-activity-read"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(bell.label, "Activity")
        app.terminate()
        app.launchArguments = ["--demo", "--demo-activity"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-button"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["activity-button"].label, "Activity, 3 unread", "Demo read markers must reset without changing real server read markers.")
    }

    func testForegroundActivityBanner() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-activity", "--demo-banner", "--reset-activity-read"]
        app.launch()
        let banner = app.buttons["activity-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        capture("Foreground activity banner")
        banner.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activity-event-4"].exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["Start cleaning"].isEnabled)
    }

    func testLiveActivityReadOnly() throws {
        guard ProcessInfo.processInfo.environment["VACUULA_LIVE_TESTS"] == "1" else { throw XCTSkip("Set VACUULA_LIVE_TESTS=1 to run an explicit read-only LAN check.") }
        let app = XCUIApplication()
        app.launchArguments = ["--read-only"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-button"].waitForExistence(timeout: 35))
        app.buttons["activity-button"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        let empty = app.descendants(matching: .any)["activity-empty"]
        let count = app.descendants(matching: .any)["activity-unread-count"]
        XCTAssertTrue(empty.waitForExistence(timeout: 15) || count.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Activity unavailable"].exists)
        capture("Live activity")
    }

    func testActivityWithLargeTextAndDarkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-activity", "--dark-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-button"].waitForExistence(timeout: 10))
        app.buttons["activity-button"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        capture("Activity — Large Text and Dark Mode")
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }
}
