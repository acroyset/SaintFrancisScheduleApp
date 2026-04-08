//
//  UsageStatsTests.swift
//  ScheduleTests
//

import Foundation
import Testing
@testable import Schedule

struct UsageStatsTests {

    @Test func rollingCountsAndTimesUseCalendarWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = makeDate(year: 2026, month: 4, day: 7, hour: 12, minute: 0, calendar: calendar)

        let storage = UsageStatsStorage(
            sessions: [
                UsageSessionRecord(
                    startedAt: makeDate(year: 2026, month: 4, day: 7, hour: 8, minute: 0, calendar: calendar),
                    endedAt: makeDate(year: 2026, month: 4, day: 7, hour: 9, minute: 0, calendar: calendar)
                ),
                UsageSessionRecord(
                    startedAt: makeDate(year: 2026, month: 4, day: 5, hour: 9, minute: 0, calendar: calendar),
                    endedAt: makeDate(year: 2026, month: 4, day: 5, hour: 9, minute: 30, calendar: calendar)
                ),
                UsageSessionRecord(
                    startedAt: makeDate(year: 2026, month: 3, day: 20, hour: 14, minute: 0, calendar: calendar),
                    endedAt: makeDate(year: 2026, month: 3, day: 20, hour: 16, minute: 0, calendar: calendar)
                ),
                UsageSessionRecord(
                    startedAt: makeDate(year: 2026, month: 2, day: 20, hour: 14, minute: 0, calendar: calendar),
                    endedAt: makeDate(year: 2026, month: 2, day: 20, hour: 14, minute: 45, calendar: calendar)
                )
            ]
        )

        let snapshot = UsageStatsCalculator.makeSnapshot(
            from: storage,
            activeSessionStart: nil,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.day.uses == 1)
        #expect(snapshot.week.uses == 2)
        #expect(snapshot.month.uses == 3)
        #expect(snapshot.lifetime.uses == 4)

        #expect(snapshot.day.totalTime == 3600)
        #expect(snapshot.week.totalTime == 5400)
        #expect(snapshot.month.totalTime == 12600)
        #expect(snapshot.lifetime.totalTime == 15300)
    }

    @Test func overlappingSessionsOnlyCountTimeInsideWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = makeDate(year: 2026, month: 4, day: 7, hour: 1, minute: 0, calendar: calendar)

        let storage = UsageStatsStorage(
            sessions: [
                UsageSessionRecord(
                    startedAt: makeDate(year: 2026, month: 4, day: 6, hour: 23, minute: 30, calendar: calendar),
                    endedAt: makeDate(year: 2026, month: 4, day: 7, hour: 0, minute: 30, calendar: calendar)
                )
            ]
        )

        let snapshot = UsageStatsCalculator.makeSnapshot(
            from: storage,
            activeSessionStart: makeDate(year: 2026, month: 4, day: 7, hour: 0, minute: 40, calendar: calendar),
            now: now,
            calendar: calendar
        )

        #expect(snapshot.day.uses == 1)
        #expect(snapshot.day.totalTime == 3000)
        #expect(snapshot.day.averageTimePerUse == 3000)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
