//
//  UsageStatsStore.swift
//  Schedule
//

import Foundation
import Combine

struct UsageSessionRecord: Codable, Equatable, Hashable {
    let startedAt: Date
    let endedAt: Date
    let appVersion: String

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

@MainActor
final class UsageStatsStore: ObservableObject {
    static let shared = UsageStatsStore()

    private var activeSessionStart: Date?

    func setUserScope(_ userId: String?) {
        activeSessionStart = nil
    }

    func beginSession(at date: Date = Date()) {
        guard activeSessionStart == nil else { return }
        activeSessionStart = date
    }

    func endSession(at date: Date = Date()) -> UsageSessionRecord? {
        guard let activeSessionStart else { return nil }

        let endedAt = max(date, activeSessionStart)
        self.activeSessionStart = nil
        return UsageSessionRecord(startedAt: activeSessionStart, endedAt: endedAt, appVersion: version)
    }
}
