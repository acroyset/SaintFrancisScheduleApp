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
}
