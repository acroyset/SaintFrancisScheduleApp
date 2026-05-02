//
//  UsageStatsStore.swift
//  Schedule
//

import Foundation
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif

enum UsagePage: String, Codable, CaseIterable {
    case home
    case news
    case classes
    case map
    case profile
}

enum UsageFeature: String, Codable, CaseIterable {
    case settings
    case eventsReminders
    case gpaCalculator
    case finalGradeCalculator
    case whatIfCalculator
    case courseBrowser
    case classEditor
}

struct UsageSessionRecord: Codable, Equatable, Hashable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let appVersion: String
    let lastPage: String?
    let pageDurations: [String: TimeInterval]
    let featureDurations: [String: TimeInterval]
    let featureCounts: [String: Int]
    let notificationsEnabled: Bool
    let liveActivitiesEnabled: Bool
    let liveActivityActive: Bool

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

@MainActor
final class UsageStatsStore: ObservableObject {
    static let shared = UsageStatsStore()

    private var activeSessionId: String?
    private var activeSessionStart: Date?
    private var currentPage: UsagePage?
    private var currentFeature: UsageFeature?
    private var currentPageStartedAt: Date?
    private var currentFeatureStartedAt: Date?
    private var pageDurations: [String: TimeInterval] = UsagePage.defaultDurations
    private var featureDurations: [String: TimeInterval] = UsageFeature.defaultDurations
    private var featureCounts: [String: Int] = UsageFeature.defaultCounts

    func setUserScope(_ userId: String?) {
        resetSession()
    }

    func beginSession(at date: Date = Date()) {
        if activeSessionStart == nil {
            activeSessionId = UUID().uuidString
            activeSessionStart = date
        }
        if currentPageStartedAt == nil, currentPage != nil {
            currentPageStartedAt = date
        }
        if currentFeatureStartedAt == nil, currentFeature != nil {
            currentFeatureStartedAt = date
        }
    }

    func currentSessionRecord(at date: Date = Date()) -> UsageSessionRecord? {
        guard let activeSessionStart,
              let activeSessionId else { return nil }

        return makeSession(
            id: activeSessionId,
            startedAt: activeSessionStart,
            endedAt: max(date, activeSessionStart)
        )
    }

    func endSession(at date: Date = Date()) -> UsageSessionRecord? {
        guard let activeSessionStart,
              let activeSessionId else { return nil }
        accumulatePageDuration(until: date)
        accumulateFeatureDuration(until: date)

        let endedAt = max(date, activeSessionStart)
        let session = makeSession(id: activeSessionId, startedAt: activeSessionStart, endedAt: endedAt)

        resetSession()
        return session
    }

    func setCurrentPage(_ page: UsagePage?, at date: Date = Date()) {
        guard currentPage != page else { return }
        accumulatePageDuration(until: date)
        currentPage = page
        currentPageStartedAt = activeSessionStart != nil && page != nil ? date : nil
    }

    func setCurrentFeature(_ feature: UsageFeature?, at date: Date = Date()) {
        guard currentFeature != feature else { return }
        accumulateFeatureDuration(until: date)
        currentFeature = feature
        if let feature {
            featureCounts[feature.rawValue, default: 0] += 1
        }
        currentFeatureStartedAt = activeSessionStart != nil && feature != nil ? date : nil
    }

    private func accumulatePageDuration(until date: Date) {
        guard let page = currentPage,
              let startedAt = currentPageStartedAt else { return }

        let duration = max(0, date.timeIntervalSince(startedAt))
        guard duration > 0 else { return }
        pageDurations[page.rawValue, default: 0] += duration
        currentPageStartedAt = date
    }

    private func accumulateFeatureDuration(until date: Date) {
        guard let feature = currentFeature,
              let startedAt = currentFeatureStartedAt else { return }

        let duration = max(0, date.timeIntervalSince(startedAt))
        guard duration > 0 else { return }
        featureDurations[feature.rawValue, default: 0] += duration
        currentFeatureStartedAt = date
    }

    private func resetSession() {
        activeSessionId = nil
        activeSessionStart = nil
        currentPage = nil
        currentFeature = nil
        currentPageStartedAt = nil
        currentFeatureStartedAt = nil
        pageDurations = UsagePage.defaultDurations
        featureDurations = UsageFeature.defaultDurations
        featureCounts = UsageFeature.defaultCounts
    }

    private func makeSession(id: String, startedAt: Date, endedAt: Date) -> UsageSessionRecord {
        UsageSessionRecord(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            appVersion: version,
            lastPage: currentPage?.rawValue,
            pageDurations: pageDurations,
            featureDurations: featureDurations,
            featureCounts: featureCounts,
            notificationsEnabled: NotificationSettings.isEnabled,
            liveActivitiesEnabled: liveActivitiesEnabled,
            liveActivityActive: liveActivityActive
        )
    }

    private var liveActivitiesEnabled: Bool {
        #if canImport(ActivityKit)
        ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        false
        #endif
    }

    private var liveActivityActive: Bool {
        #if canImport(ActivityKit)
        Activity<ScheduleWidgetAttributes>.activities.contains {
            switch $0.activityState {
            case .active, .stale:
                return true
            default:
                return false
            }
        }
        #else
        false
        #endif
    }
}

private extension UsagePage {
    static var defaultDurations: [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, 0) })
    }
}

private extension UsageFeature {
    static var defaultDurations: [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, 0) })
    }

    static var defaultCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, 0) })
    }
}
