//
//  CloudService.swift
//  Schedule
//

import Foundation
import Network

extension Notification.Name {
    static let cloudConnectivityChanged = Notification.Name("CloudConnectivityChanged")
}

protocol CloudConnectivityChecking: AnyObject {
    var isConnected: Bool { get }
}

final class NetworkCloudConnectivity: CloudConnectivityChecking, @unchecked Sendable {
    static let shared = NetworkCloudConnectivity()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Schedule.CloudConnectivity")
    private let lock = NSLock()
    private var connected = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.setConnected(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    private func setConnected(_ value: Bool) {
        lock.lock()
        let changed = connected != value
        connected = value
        lock.unlock()

        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cloudConnectivityChanged, object: nil)
            }
        }
    }
}

enum CloudConnectivityError: LocalizedError {
    case offline

    var errorDescription: String? {
        "No internet connection. Your changes are saved on this device and waiting to upload."
    }
}

enum CloudAppStateSaveError: LocalizedError, Equatable {
    case managedSyncRequired

    var errorDescription: String? {
        "Whole-app saves must use the managed schedule and events sync so data-recovery safeguards stay active."
    }
}

struct PersistedThemeState {
    let primary: String
    let secondary: String
    let tertiary: String
    let primaryFontChoice: AppFontChoice
    let secondaryFontChoice: AppFontChoice

    init(theme: ThemeColors) {
        primary = theme.primary
        secondary = theme.secondary
        tertiary = theme.tertiary
        primaryFontChoice = theme.primaryFontChoice
        secondaryFontChoice = theme.secondaryFontChoice
    }
}

struct PersistedScheduleState {
    let classes: [ClassItem]
    let days: [Day]
    let isSecondLunch: [Bool]
    let theme: PersistedThemeState
    /// False only when the account has no schedule payload at all. An
    /// encrypted empty class array is authoritative and represents a real
    /// cross-device deletion.
    let isAuthoritative: Bool

    init(
        classes: [ClassItem],
        days: [Day],
        isSecondLunch: [Bool],
        theme: PersistedThemeState,
        isAuthoritative: Bool = true
    ) {
        self.classes = classes
        self.days = days
        self.isSecondLunch = isSecondLunch
        self.theme = theme
        self.isAuthoritative = isAuthoritative
    }

    var normalizedData: ScheduleData {
        ScheduleData(classes: classes, days: days, isSecondLunch: isSecondLunch).normalized()
    }
}

struct PersistedAppState {
    let schedule: PersistedScheduleState
    let events: [CustomEvent]
}

enum CloudSyncPhase: Equatable {
    case disconnected
    case loading
    case synced
    case pending
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "On this device"
        case .loading: "Connecting…"
        case .synced: "Up to date"
        case .pending: "Saving changes…"
        case .failed: "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected: "iphone"
        case .loading: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud.fill"
        case .pending: "icloud.and.arrow.up"
        case .failed: "exclamationmark.icloud.fill"
        }
    }
}

/// Type-erased lifetime for a Firestore snapshot listener. Keeping this out of
/// the view models means tests and previews do not need to import Firebase.
@MainActor
final class CloudSyncObservation {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }

    deinit {
        cancellation?()
    }
}

@MainActor
protocol ScheduleCloudSyncing: AnyObject {
    func saveScheduleToCloud(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        userId: String
    ) async throws

    func loadCloudScheduleState(
        for userId: String,
        days: [Day]
    ) async throws -> PersistedScheduleState

    func observeCloudScheduleState(
        for userId: String,
        days: [Day],
        onChange: @escaping @MainActor (Result<PersistedScheduleState, Error>) -> Void
    ) -> CloudSyncObservation?
}

extension ScheduleCloudSyncing {
    func observeCloudScheduleState(
        for userId: String,
        days: [Day],
        onChange: @escaping @MainActor (Result<PersistedScheduleState, Error>) -> Void
    ) -> CloudSyncObservation? {
        nil
    }
}

@MainActor
final class CloudService: ScheduleCloudSyncing {
    private lazy var dataManager = DataManager()
    private lazy var eventsDataManager = CloudEventsDataManager.shared
    private let userDefaults: UserDefaults
    private let customEventsKey = "CustomEvents"
    private let localLunchKey = "LocalIsSecondLunch"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    init(dataManager: DataManager, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.dataManager = dataManager
    }

    func loadLocalClasses(parseClass: (String) -> ClassItem) -> [ClassItem] {
        do {
            let url = try ensureWritableClassesFile()
            let contents = try String(contentsOf: url, encoding: .utf8)
            return contents.split(whereSeparator: \.isNewline).map { parseClass(String($0)) }
        } catch {
            print("❌ Failed to load Classes from Documents:", error)
            return []
        }
    }

    func loadBundledDays(parseDays: (String) -> [Day]) -> [Day]? {
        guard let daysURL = Bundle.main.url(forResource: "Days", withExtension: "txt") else {
            return nil
        }

        let daysContents = (try? String(contentsOf: daysURL, encoding: .utf8)) ?? ""
        return parseDays(daysContents)
    }

    func loadLocalSchedule(
        parseClass: (String) -> ClassItem,
        parseDays: (String) -> [Day]
    ) -> PersistedScheduleState? {
        guard let days = loadBundledDays(parseDays: parseDays) else { return nil }

        return PersistedScheduleState(
            classes: loadLocalClasses(parseClass: parseClass),
            days: days,
            isSecondLunch: loadLunchPreferenceLocally(),
            theme: PersistedThemeState(theme: loadThemeLocally() ?? .defaultTheme)
        )
    }

    func saveThemeLocally(_ theme: ThemeColors) {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        userDefaults.set(data, forKey: "LocalTheme")
        SharedGroup.defaults.set(data, forKey: "ThemeColors")
        WidgetManager.shared.saveTheme(theme)
    }

    func loadThemeLocally() -> ThemeColors? {
        guard let data = userDefaults.data(forKey: "LocalTheme"),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else {
            return nil
        }
        return theme
    }

    func saveLunchPreferenceLocally(_ isSecondLunch: [Bool]) {
        let normalized = ScheduleData(
            classes: [],
            days: [],
            isSecondLunch: isSecondLunch
        ).normalized().isSecondLunch
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        userDefaults.set(data, forKey: localLunchKey)
    }

    func loadLunchPreferenceLocally() -> [Bool] {
        guard let data = userDefaults.data(forKey: localLunchKey),
              let value = try? JSONDecoder().decode([Bool].self, from: data) else {
            return [false, false]
        }
        return ScheduleData(classes: [], days: [], isSecondLunch: value)
            .normalized()
            .isSecondLunch
    }

    func saveEventsLocally(_ events: [CustomEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        userDefaults.set(data, forKey: customEventsKey)
        SharedGroup.defaults.set(data, forKey: customEventsKey)
    }

    func loadEventsLocally() -> [CustomEvent] {
        guard let data = userDefaults.data(forKey: customEventsKey),
              let events = try? JSONDecoder().decode([CustomEvent].self, from: data) else {
            return []
        }
        return events
    }

    func saveAppState(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        events: [CustomEvent],
        userId: String?
    ) async throws {
        // A direct whole-app save has no access to GlobalDataStore's and
        // CustomEventsManager's account-scoped corruption fences. In
        // particular, creating fresh cloud writers here could turn a blank UI
        // produced by a corrupt account activation into an authoritative
        // overwrite. All saves must instead enter through those managers.
        throw CloudAppStateSaveError.managedSyncRequired
    }

    func loadAppState(
        userId: String?,
        parseClass: (String) -> ClassItem,
        parseDays: (String) -> [Day]
    ) async throws -> PersistedAppState? {
        guard let localSchedule = loadLocalSchedule(parseClass: parseClass, parseDays: parseDays) else {
            return nil
        }

        let localEvents = loadEventsLocally()

        guard let userId else {
            return PersistedAppState(schedule: localSchedule, events: localEvents)
        }

        async let cloudScheduleTask = loadCloudScheduleState(
            for: userId,
            days: localSchedule.days
        )
        async let cloudEventsTask = eventsDataManager.loadEventState(for: userId)
        let (cloudSchedule, cloudEvents) = try await (cloudScheduleTask, cloudEventsTask)

        let mergedSchedule = Self.resolveLoadedSchedule(
            local: localSchedule,
            cloud: cloudSchedule
        )
        let mergedEvents = Self.resolveLoadedEvents(
            local: localEvents,
            cloud: cloudEvents
        )

        overwriteClassesFile(with: mergedSchedule.normalizedData.classes)
        saveThemeLocally(ThemeColors(
            primary: mergedSchedule.theme.primary,
            secondary: mergedSchedule.theme.secondary,
            tertiary: mergedSchedule.theme.tertiary,
            primaryFont: mergedSchedule.theme.primaryFontChoice,
            secondaryFont: mergedSchedule.theme.secondaryFontChoice
        ))
        saveLunchPreferenceLocally(mergedSchedule.isSecondLunch)
        saveEventsLocally(mergedEvents)

        return PersistedAppState(schedule: mergedSchedule, events: mergedEvents)
    }

    static func resolveLoadedSchedule(
        local: PersistedScheduleState,
        cloud: PersistedScheduleState
    ) -> PersistedScheduleState {
        cloud.isAuthoritative ? cloud : local
    }

    static func resolveLoadedEvents(
        local: [CustomEvent],
        cloud: PersistedEventsState
    ) -> [CustomEvent] {
        cloud.isAuthoritative ? cloud.events : local
    }

    func saveScheduleToCloud(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        userId: String
    ) async throws {
        try await dataManager.saveToCloud(
            classes: classes,
            theme: theme,
            isSecondLunch: isSecondLunch,
            for: userId
        )
    }

    func loadScheduleFromCloud(for userId: String) async throws -> ([ClassItem], ThemeColors, [Bool]) {
        try await dataManager.loadFromCloud(for: userId)
    }

    func loadCloudScheduleState(for userId: String, days: [Day]) async throws -> PersistedScheduleState {
        let (classes, theme, isSecondLunch) = try await loadScheduleFromCloud(for: userId)
        return PersistedScheduleState(
            classes: classes,
            days: days,
            isSecondLunch: isSecondLunch,
            theme: PersistedThemeState(theme: theme),
            isAuthoritative: dataManager.lastScheduleLoadWasAuthoritative
        )
    }

    func observeCloudScheduleState(
        for userId: String,
        days: [Day],
        onChange: @escaping @MainActor (Result<PersistedScheduleState, Error>) -> Void
    ) -> CloudSyncObservation? {
        dataManager.observeSchedule(for: userId) { result in
            onChange(result.map { classes, theme, isSecondLunch, isAuthoritative in
                PersistedScheduleState(
                    classes: classes,
                    days: days,
                    isSecondLunch: isSecondLunch,
                    theme: PersistedThemeState(theme: theme),
                    isAuthoritative: isAuthoritative
                )
            })
        }
    }

    func appendUsageSessionToCloud(_ session: UsageSessionRecord, for userId: String) async throws {
        try await dataManager.appendUsageSessionToCloud(session, for: userId)
    }

    func clearUsageStats(for userId: String) async throws {
        try await dataManager.clearUsageStats(for: userId)
        UsageStatsStore.shared.rotateSessionAfterClear()
    }
}
