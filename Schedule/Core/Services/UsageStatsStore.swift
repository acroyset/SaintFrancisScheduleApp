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
    case events
    case reminders
    case homework
    case gpaCalculator
    case finalGradeCalculator
    case whatIfCalculator
    case courseBrowser
    case classEditor
}

enum UsageItemKind: String, Codable, CaseIterable {
    case homework
    case reminder = "reminders"
    case event = "events"
}

enum UsageItemAction: String, Codable, CaseIterable {
    case create
    case edit
    case complete
    case delete
    case open
}

enum UsageNewsTab: String, Codable, CaseIterable {
    case dailyAnnouncements
    case lancerLive
    case athletics
}

struct UsageSessionRecord: Codable, Equatable, Hashable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let appVersion: String
    let lastPage: String?
    let pageDurations: [String: TimeInterval]
    let featureDurations: [String: TimeInterval]
    let featureViewCounts: [String: Int]
    let itemActionCounts: [String: [String: Int]]
    let newsTabDurations: [String: TimeInterval]
    let newsTabViewCounts: [String: Int]
    let notificationsEnabled: Bool
    let liveActivitiesEnabled: Bool
    let liveActivityActive: Bool
}

@MainActor
final class UsageStatsStore: ObservableObject {
    static let shared = UsageStatsStore()

    private var userScope: String?
    private var activeSessionId: String?
    private var activeSessionStart: Date?
    private var currentPage: UsagePage?
    private var currentFeature: UsageFeature?
    private var currentNewsTab: UsageNewsTab?
    private var currentPageStartedAt: Date?
    private var currentFeatureStartedAt: Date?
    private var currentNewsTabStartedAt: Date?
    private var pageDurations: [String: TimeInterval] = UsagePage.defaultDurations
    private var featureDurations: [String: TimeInterval] = UsageFeature.defaultDurations
    private var featureViewCounts: [String: Int] = UsageFeature.defaultCounts
    private var itemActionCounts: [String: [String: Int]] = UsageItemKind.defaultActionCounts
    private var newsTabDurations: [String: TimeInterval] = UsageNewsTab.defaultDurations
    private var newsTabViewCounts: [String: Int] = UsageNewsTab.defaultCounts

    func setUserScope(_ userId: String?) {
        guard userScope != userId else { return }
        userScope = userId
        resetSession()
    }

    func beginSession(at date: Date = Date()) {
        let isNewSession = activeSessionStart == nil
        if isNewSession {
            activeSessionId = UUID().uuidString
            activeSessionStart = date
            if let currentFeature {
                featureViewCounts[currentFeature.rawValue, default: 0] += 1
            }
            if let currentNewsTab {
                newsTabViewCounts[currentNewsTab.rawValue, default: 0] += 1
            }
        }
        if currentPageStartedAt == nil, currentPage != nil {
            currentPageStartedAt = date
        }
        if currentFeatureStartedAt == nil, currentFeature != nil {
            currentFeatureStartedAt = date
        }
        if currentNewsTabStartedAt == nil, currentNewsTab != nil {
            currentNewsTabStartedAt = date
        }
    }

    func pauseSession(at date: Date = Date()) -> UsageSessionRecord? {
        guard let session = snapshotSession(at: date) else { return nil }
        currentPageStartedAt = nil
        currentFeatureStartedAt = nil
        currentNewsTabStartedAt = nil
        return session
    }

    func snapshotSession(at date: Date = Date()) -> UsageSessionRecord? {
        guard let activeSessionStart,
              let activeSessionId else { return nil }
        accumulatePageDuration(until: date)
        accumulateFeatureDuration(until: date)
        accumulateNewsTabDuration(until: date)

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
        accumulateNewsTabDuration(until: date)

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
        if let feature, activeSessionStart != nil {
            featureViewCounts[feature.rawValue, default: 0] += 1
        }
        currentFeatureStartedAt = activeSessionStart != nil && feature != nil ? date : nil
    }

    func setCurrentNewsTab(_ tab: UsageNewsTab?, at date: Date = Date()) {
        guard currentNewsTab != tab else { return }
        accumulateNewsTabDuration(until: date)
        currentNewsTab = tab
        if let tab, activeSessionStart != nil {
            newsTabViewCounts[tab.rawValue, default: 0] += 1
        }
        currentNewsTabStartedAt = activeSessionStart != nil && tab != nil ? date : nil
    }

    func recordItemAction(_ action: UsageItemAction, for kind: UsageItemKind) {
        guard activeSessionStart != nil else { return }

        var actionCounts = itemActionCounts[kind.rawValue] ?? UsageItemAction.defaultCounts
        actionCounts[action.rawValue, default: 0] += 1
        itemActionCounts[kind.rawValue] = actionCounts
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

    private func accumulateNewsTabDuration(until date: Date) {
        guard let tab = currentNewsTab,
              let startedAt = currentNewsTabStartedAt else { return }

        let duration = max(0, date.timeIntervalSince(startedAt))
        guard duration > 0 else { return }
        newsTabDurations[tab.rawValue, default: 0] += duration
        currentNewsTabStartedAt = date
    }

    private func resetSession() {
        activeSessionId = nil
        activeSessionStart = nil
        currentPage = nil
        currentFeature = nil
        currentNewsTab = nil
        currentPageStartedAt = nil
        currentFeatureStartedAt = nil
        currentNewsTabStartedAt = nil
        pageDurations = UsagePage.defaultDurations
        featureDurations = UsageFeature.defaultDurations
        featureViewCounts = UsageFeature.defaultCounts
        itemActionCounts = UsageItemKind.defaultActionCounts
        newsTabDurations = UsageNewsTab.defaultDurations
        newsTabViewCounts = UsageNewsTab.defaultCounts
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
            featureViewCounts: featureViewCounts,
            itemActionCounts: itemActionCounts,
            newsTabDurations: newsTabDurations,
            newsTabViewCounts: newsTabViewCounts,
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

private extension UsageItemKind {
    static var defaultActionCounts: [String: [String: Int]] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, UsageItemAction.defaultCounts) })
    }
}

private extension UsageItemAction {
    static var defaultCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, 0) })
    }
}

private extension UsageNewsTab {
    static var defaultDurations: [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, 0) })
    }

    static var defaultCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, 0) })
    }
}
