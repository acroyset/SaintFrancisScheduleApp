//
//  ScheduleUITests.swift
//  ScheduleUITests
//
//  Created by Andreas Royset on 8/13/25.
//

import XCTest

final class ScheduleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeworkSheetExposesControlsAndCoversRefreshStatus() throws {
        let app = launchTestApp(
            additionalArguments: ["-ui-testing-active-schedule-retry"]
        )

        let refreshStatus = app.staticTexts["schedule.refresh-status"]
        XCTAssertTrue(refreshStatus.waitForExistence(timeout: 3))

        let addMenu = app.buttons["home.add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(refreshStatus.frame.maxY, addMenu.frame.minY - 4)
        addMenu.tap()

        let addHomework = app.buttons["home.add-homework"]
        XCTAssertTrue(addHomework.waitForExistence(timeout: 2))
        XCTAssertFalse(refreshStatus.exists)
        addHomework.tap()

        XCTAssertTrue(app.navigationBars["Add Homework"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-homework.cancel"].exists)
        XCTAssertTrue(app.buttons["add-homework.save"].exists)
        XCTAssertFalse(refreshStatus.exists)

        app.buttons["add-homework.cancel"].tap()
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3))
    }

    @MainActor
    func testRefreshFailureDoesNotOverlapExpandedAddMenu() throws {
        let app = launchTestApp(
            additionalArguments: ["-ui-testing-schedule-refresh-failure"]
        )

        let loadError = app.staticTexts["schedule.load-error"]
        XCTAssertTrue(loadError.waitForExistence(timeout: 3))

        let addMenu = app.buttons["home.add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(loadError.frame.maxY, addMenu.frame.minY - 4)

        addMenu.tap()
        XCTAssertTrue(app.buttons["home.add-homework"].waitForExistence(timeout: 2))
        XCTAssertFalse(loadError.exists)
    }

    @MainActor
    func testProfileSettingsAndGraphiteThemeAreAccessible() throws {
        let app = launchTestApp()

        app.buttons["toolbar.profile"].tap()
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertEqual(settings.label, "Settings")
        settings.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        let graphite = app.buttons["theme.graphite"]
        XCTAssertTrue(graphite.waitForExistence(timeout: 3))
        graphite.tap()
        XCTAssertEqual(graphite.value as? String, "Selected")
    }

    @MainActor
    func testNightlyNotificationsCanBeEnabledInUITestMode() throws {
        let app = launchTestApp()

        app.buttons["toolbar.profile"].tap()
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let toggle = app.switches["settings.nightly-notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.staticTexts["Settings"].exists)
    }

    @MainActor
    func testEventsAndRemindersSheetExposesCloseAndFilterControls() throws {
        let app = launchTestApp()

        app.buttons["toolbar.profile"].tap()
        let allItems = app.buttons["View Events & Reminders"]
        XCTAssertTrue(allItems.waitForExistence(timeout: 3))
        allItems.tap()

        XCTAssertTrue(app.navigationBars["Events & Reminders"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["all-items.close"].exists)
        XCTAssertTrue(app.buttons["all-items.filter-sort"].exists)
        app.buttons["all-items.close"].tap()
        XCTAssertTrue(allItems.waitForExistence(timeout: 3))
    }

    @MainActor
    func testToolbarNavigatesFromEdgesOfExpandedHitRegions() throws {
        let app = launchTestApp()

        let news = app.buttons["toolbar.news"]
        XCTAssertTrue(news.waitForExistence(timeout: 3))
        news.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Saint Francis News"].waitForExistence(timeout: 3))

        let classes = app.buttons["toolbar.classes"]
        XCTAssertTrue(classes.waitForExistence(timeout: 3))
        classes.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Classes"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testIPadLandscapeHomeControlsStayWithinTheWindow() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchTestApp()
        let windowFrame = app.windows.firstMatch.frame

        let noClassesTitle = app.staticTexts["home.day-title"]
        XCTAssertTrue(noClassesTitle.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(noClassesTitle.frame.minX, windowFrame.minX)

        let addMenu = app.buttons["home.add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(addMenu.frame.maxX, windowFrame.maxX)
    }

    @MainActor
    func testIPhoneLandscapeExpandedAddMenuDoesNotCoverToolbar() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchTestApp()
        let addMenu = app.buttons["home.add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3))
        addMenu.tap()

        let addButtons = ["event", "reminder", "homework"].map {
            app.buttons["home.add-\($0)"]
        }
        XCTAssertTrue(addButtons.allSatisfy { $0.waitForExistence(timeout: 2) })

        let toolbarButtons = ["home", "news", "classes", "map", "profile"].map {
            app.buttons["toolbar.\($0)"]
        }
        XCTAssertTrue(toolbarButtons.allSatisfy(\.isHittable))

        for addButton in addButtons {
            for toolbarButton in toolbarButtons {
                XCTAssertFalse(addButton.frame.intersects(toolbarButton.frame))
            }
        }
    }

    @MainActor
    func testGraphiteRefreshStatusRemainsVisible() throws {
        let app = launchTestApp(
            additionalArguments: [
                "-ui-testing-active-schedule-retry",
                "-ui-testing-graphite-theme"
            ]
        )

        let refreshStatus = app.staticTexts["schedule.refresh-status"]
        XCTAssertTrue(refreshStatus.waitForExistence(timeout: 3))
        XCTAssertEqual(refreshStatus.label, "Refreshing schedule…")
    }

    @MainActor
    private func launchTestApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchArguments.append(contentsOf: additionalArguments)
        app.launch()
        XCTAssertTrue(app.buttons["toolbar.home"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            // Intentionally use the same startup path as a production launch.
            // Functional UI tests use -ui-testing for deterministic fixtures;
            // this benchmark must include service and system registration.
            XCUIApplication().launch()
        }
    }

}
