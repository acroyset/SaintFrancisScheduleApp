import XCTest
@testable import Schedule

final class UsageStatsStoreTests: XCTestCase {
    @MainActor
    func testItemActionCountsAreRecordedByKindAndAction() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        store.beginSession(at: startedAt)

        for kind in UsageItemKind.allCases {
            for action in UsageItemAction.allCases {
                store.recordItemAction(action, for: kind)
            }
        }

        let session = try XCTUnwrap(store.endSession(at: startedAt.addingTimeInterval(10)))

        for kind in UsageItemKind.allCases {
            for action in UsageItemAction.allCases {
                XCTAssertEqual(session.itemActionCounts[kind.rawValue]?[action.rawValue], 1)
            }
        }
    }

    @MainActor
    func testItemActionsAreSessionScopedAndResetAfterEnding() throws {
        let store = UsageStatsStore()
        store.recordItemAction(.create, for: .homework)

        let firstStart = Date(timeIntervalSince1970: 2_000)
        store.beginSession(at: firstStart)
        store.recordItemAction(.create, for: .homework)
        let firstSession = try XCTUnwrap(store.endSession(at: firstStart.addingTimeInterval(5)))

        let secondStart = Date(timeIntervalSince1970: 3_000)
        store.beginSession(at: secondStart)
        let secondSession = try XCTUnwrap(store.endSession(at: secondStart.addingTimeInterval(5)))

        XCTAssertEqual(firstSession.itemActionCounts[UsageItemKind.homework.rawValue]?[UsageItemAction.create.rawValue], 1)
        XCTAssertEqual(secondSession.itemActionCounts[UsageItemKind.homework.rawValue]?[UsageItemAction.create.rawValue], 0)
    }

    @MainActor
    func testFeatureViewsAndItemActionsRemainDistinct() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 4_000)
        store.beginSession(at: startedAt)
        store.setCurrentFeature(.events, at: startedAt)
        store.recordItemAction(.open, for: .event)
        store.recordItemAction(.edit, for: .event)

        let session = try XCTUnwrap(store.endSession(at: startedAt.addingTimeInterval(5)))

        XCTAssertEqual(
            session.featureViewCounts[UsageFeature.events.rawValue],
            1
        )
        XCTAssertEqual(
            session.itemActionCounts[UsageItemKind.event.rawValue]?[UsageItemAction.open.rawValue],
            1
        )
        XCTAssertEqual(
            session.itemActionCounts[UsageItemKind.event.rawValue]?[UsageItemAction.edit.rawValue],
            1
        )
    }

    @MainActor
    func testNewsTabsTrackRawViewsAndDurations() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 6_000)
        store.beginSession(at: startedAt)

        store.setCurrentNewsTab(.dailyAnnouncements, at: startedAt)
        store.setCurrentNewsTab(.lancerLive, at: startedAt.addingTimeInterval(2))
        store.setCurrentNewsTab(.athletics, at: startedAt.addingTimeInterval(5))
        store.setCurrentNewsTab(nil, at: startedAt.addingTimeInterval(9))

        let session = try XCTUnwrap(store.endSession(at: startedAt.addingTimeInterval(10)))

        XCTAssertEqual(session.newsTabViewCounts[UsageNewsTab.dailyAnnouncements.rawValue], 1)
        XCTAssertEqual(session.newsTabDurations[UsageNewsTab.dailyAnnouncements.rawValue], 2)
        XCTAssertEqual(session.newsTabViewCounts[UsageNewsTab.lancerLive.rawValue], 1)
        XCTAssertEqual(session.newsTabDurations[UsageNewsTab.lancerLive.rawValue], 3)
        XCTAssertEqual(session.newsTabViewCounts[UsageNewsTab.athletics.rawValue], 1)
        XCTAssertEqual(session.newsTabDurations[UsageNewsTab.athletics.rawValue], 4)
    }

    @MainActor
    func testNewsTabMetricsResetBetweenSessions() throws {
        let store = UsageStatsStore()
        let firstStart = Date(timeIntervalSince1970: 7_000)
        store.beginSession(at: firstStart)
        store.setCurrentNewsTab(.athletics, at: firstStart)
        _ = store.endSession(at: firstStart.addingTimeInterval(3))

        let secondStart = Date(timeIntervalSince1970: 8_000)
        store.beginSession(at: secondStart)
        let secondSession = try XCTUnwrap(store.endSession(at: secondStart.addingTimeInterval(3)))

        for tab in UsageNewsTab.allCases {
            XCTAssertEqual(secondSession.newsTabViewCounts[tab.rawValue], 0)
            XCTAssertEqual(secondSession.newsTabDurations[tab.rawValue], 0)
        }
    }

    @MainActor
    func testPauseAndResumeKeepsOneSessionWithoutCountingInactiveTime() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 9_000)
        store.beginSession(at: startedAt)
        store.setCurrentPage(.news, at: startedAt)
        store.setCurrentNewsTab(.athletics, at: startedAt)

        let checkpoint = try XCTUnwrap(
            store.pauseSession(at: startedAt.addingTimeInterval(2))
        )
        store.beginSession(at: startedAt.addingTimeInterval(10))
        let session = try XCTUnwrap(store.endSession(at: startedAt.addingTimeInterval(13)))

        XCTAssertEqual(checkpoint.id, session.id)
        XCTAssertEqual(checkpoint.pageDurations[UsagePage.news.rawValue], 2)
        XCTAssertEqual(checkpoint.newsTabDurations[UsageNewsTab.athletics.rawValue], 2)
        XCTAssertEqual(session.startedAt, startedAt)
        XCTAssertEqual(session.pageDurations[UsagePage.news.rawValue], 5)
        XCTAssertEqual(session.newsTabDurations[UsageNewsTab.athletics.rawValue], 5)
        XCTAssertEqual(session.newsTabViewCounts[UsageNewsTab.athletics.rawValue], 1)
    }

    @MainActor
    func testActiveSnapshotsKeepTrackingWithTheSameSessionID() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 9_500)
        store.beginSession(at: startedAt)
        store.setCurrentPage(.classes, at: startedAt)

        let firstSnapshot = try XCTUnwrap(
            store.snapshotSession(at: startedAt.addingTimeInterval(2))
        )
        let secondSnapshot = try XCTUnwrap(
            store.snapshotSession(at: startedAt.addingTimeInterval(5))
        )

        XCTAssertEqual(firstSnapshot.id, secondSnapshot.id)
        XCTAssertEqual(firstSnapshot.pageDurations[UsagePage.classes.rawValue], 2)
        XCTAssertEqual(secondSnapshot.pageDurations[UsagePage.classes.rawValue], 5)
    }

    @MainActor
    func testSettingTheSameUserScopeDoesNotResetAnActiveSession() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 10_000)
        store.setUserScope("user")
        store.beginSession(at: startedAt)
        store.recordItemAction(.create, for: .homework)

        store.setUserScope("user")
        let session = try XCTUnwrap(store.endSession(at: startedAt.addingTimeInterval(1)))

        XCTAssertEqual(
            session.itemActionCounts[UsageItemKind.homework.rawValue]?[UsageItemAction.create.rawValue],
            1
        )
    }
}
