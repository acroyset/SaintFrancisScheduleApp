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

@MainActor
final class CloudService {
    private let dataManager: DataManager

    init() {
        self.dataManager = DataManager()
    }

    init(dataManager: DataManager) {
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

    func touchCloudLastUpdated(for userId: String) async throws {
        try await dataManager.touchLastUpdated(for: userId)
    }

    func appendUsageSessionToCloud(_ session: UsageSessionRecord, for userId: String) async throws {
        try await dataManager.appendUsageSessionToCloud(session, for: userId)
    }

    func clearUsageStats(for userId: String) async throws {
        try await dataManager.clearUsageStats(for: userId)
    }
}
