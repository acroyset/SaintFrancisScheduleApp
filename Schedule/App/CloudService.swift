//
//  CloudService.swift
//  Schedule
//

import Foundation

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

    var normalizedData: ScheduleData {
        ScheduleData(classes: classes, days: days, isSecondLunch: isSecondLunch).normalized()
    }
}

struct PersistedAppState {
    let schedule: PersistedScheduleState
    let events: [CustomEvent]
}

@MainActor
final class CloudService {
    private let dataManager: DataManager
    private let eventsDataManager: CloudEventsDataManager
    private let userDefaults = UserDefaults.standard
    private let customEventsKey = "CustomEvents"

    init() {
        self.dataManager = DataManager()
        self.eventsDataManager = CloudEventsDataManager()
    }

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        self.eventsDataManager = CloudEventsDataManager()
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
            isSecondLunch: [false, false],
            theme: PersistedThemeState(theme: loadThemeLocally() ?? .defaultTheme)
        )
    }

    func saveThemeLocally(_ theme: ThemeColors) {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        UserDefaults.standard.set(data, forKey: "LocalTheme")
        SharedGroup.defaults.set(data, forKey: "ThemeColors")
        WidgetManager.shared.saveTheme(theme)
    }

    func loadThemeLocally() -> ThemeColors? {
        guard let data = UserDefaults.standard.data(forKey: "LocalTheme"),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else {
            return nil
        }
        return theme
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
        overwriteClassesFile(with: classes)
        saveThemeLocally(theme)
        saveEventsLocally(events)

        guard let userId else { return }

        async let saveScheduleTask: Void = saveScheduleToCloud(
            classes: classes,
            theme: theme,
            isSecondLunch: isSecondLunch,
            userId: userId
        )
        async let saveEventsTask: Void = eventsDataManager.saveEvents(events, for: userId)
        _ = try await (saveScheduleTask, saveEventsTask)
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

        do {
            async let cloudScheduleTask = loadCloudScheduleState(for: userId, days: localSchedule.days)
            async let cloudEventsTask = eventsDataManager.loadEvents(for: userId)
            let (cloudSchedule, cloudEvents) = try await (cloudScheduleTask, cloudEventsTask)

            let mergedSchedule = cloudSchedule.classes.isEmpty
                ? localSchedule
                : cloudSchedule
            let mergedEvents = cloudEvents.isEmpty
                ? localEvents
                : cloudEvents

            overwriteClassesFile(with: mergedSchedule.normalizedData.classes)
            saveThemeLocally(ThemeColors(
                primary: mergedSchedule.theme.primary,
                secondary: mergedSchedule.theme.secondary,
                tertiary: mergedSchedule.theme.tertiary,
                primaryFont: mergedSchedule.theme.primaryFontChoice,
                secondaryFont: mergedSchedule.theme.secondaryFontChoice
            ))
            saveEventsLocally(mergedEvents)

            return PersistedAppState(schedule: mergedSchedule, events: mergedEvents)
        } catch {
            return PersistedAppState(schedule: localSchedule, events: localEvents)
        }
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
            theme: PersistedThemeState(theme: theme)
        )
    }

    func appendUsageSessionToCloud(_ session: UsageSessionRecord, for userId: String) async throws {
        try await dataManager.appendUsageSessionToCloud(session, for: userId)
    }

    func clearUsageStats(for userId: String) async throws {
        try await dataManager.clearUsageStats(for: userId)
    }
}
