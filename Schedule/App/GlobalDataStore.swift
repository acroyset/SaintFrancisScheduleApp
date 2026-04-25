//
//  GlobalDataStore.swift
//  Schedule
//

import Foundation
import SwiftUI

@MainActor
final class GlobalDataStore: ObservableObject {
    @Published var output = "Loading…"
    @Published var dayCode = ""
    @Published var note = ""
    @Published var scheduleDict: [String: [String]]? = nil
    @Published var scheduleLines: [ScheduleLine] = []
    @Published var data: ScheduleData? = nil
    @Published var selectedDate = Date()
    @Published var scheduleLoadError: String? = nil
    @Published var scheduleRetryAttempt: Int = 0

    @Published var primaryColor: Color = .blue
    @Published var secondaryColor: Color = .blue.opacity(0.1)
    @Published var tertiaryColor: Color = .primary
    @Published var primaryFontChoice: AppFontChoice = .rounded
    @Published var secondaryFontChoice: AppFontChoice = .rounded

    private let persistence = CloudService()

    private var themeDebounceTask: Task<Void, Never>?
    private var lastSavedTheme: ThemeColors?
    private var hasTriedFetchingSchedule = false
    private var hasLoadedFromCloud = false

    var currentTheme: ThemeColors {
        ThemeColors(
            primary: primaryColor.toHex() ?? "#00A5FFFF",
            secondary: secondaryColor.toHex() ?? "#00A5FF19",
            tertiary: tertiaryColor.toHex() ?? "#FFFFFFFF",
            primaryFont: primaryFontChoice,
            secondaryFont: secondaryFontChoice
        )
    }

    func loadData(
        authManager: AuthenticationManager,
        eventsManager: CustomEventsManager,
        onboardingClasses: [ClassItem]
    ) {
        guard data == nil else { return }

        applyLocalData(onboardingClasses: onboardingClasses)
        syncCloudData(authManager: authManager)
        eventsManager.setAuthManager(authManager)
        eventsManager.loadFromCloud(using: authManager)

        if !hasTriedFetchingSchedule {
            hasTriedFetchingSchedule = true
            fetchScheduleFromGoogleSheets(events: eventsManager.events)
        }
    }

    func saveTheme(authManager: AuthenticationManager) {
        saveThemeLocally(currentTheme)
        if authManager.user != nil {
            debouncedCloudSave(authManager: authManager, theme: currentTheme)
        }
    }

    func saveSchedule(authManager: AuthenticationManager) {
        guard let user = authManager.user, let data else { return }

        Task {
            do {
                try await persistence.saveScheduleToCloud(
                    classes: data.classes,
                    theme: currentTheme,
                    isSecondLunch: data.isSecondLunch,
                    userId: user.id
                )
                overwriteClassesFile(with: data.classes)
            } catch {
                print("❌ Failed to save classes to cloud: \(error)")
            }
        }
    }

    func getDayInfo(for currentDay: String) -> Day? {
        let dayIndex = getDayNumber(for: currentDay) ?? 0
        return data?.days[dayIndex]
    }

    func applySelectedDate(_ date: Date, events: [CustomEvent]) {
        selectedDate = date
        let resolved = ScheduleSelectionResolver.resolve(
            selectedDate: date,
            scheduleDict: scheduleDict,
            data: data,
            events: events
        )

        dayCode = resolved.dayCode
        note = resolved.note
        output = resolved.output
        scheduleLines = resolved.scheduleLines
        SharedGroup.defaults.set(dayCode == "None" ? "" : dayCode, forKey: "CurrentDayCode")
    }

    func syncDerivedOutputs(events: [CustomEvent]) {
        refreshRenderedSchedule(events: events)
        saveScheduleLinesWithEvents(events: events)
        saveDataForWidget()
        updateLiveActivity()
    }

    func refreshAllData(
        authManager: AuthenticationManager,
        events: [CustomEvent]
    ) async {
        await fetchScheduleFromGoogleSheetsAsync(events: events)
        if let user = authManager.user {
            do {
                let (cloudClasses, theme, _) = try await persistence.loadScheduleFromCloud(for: user.id)
                if !cloudClasses.isEmpty, var currentData = data {
                    currentData.classes = cloudClasses
                    data = currentData.normalized()
                    overwriteClassesFile(with: data?.classes ?? cloudClasses)
                }
                applyTheme(theme)
                SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
                refreshRenderedSchedule(events: events)
                saveScheduleLinesWithEvents(events: events)
                saveThemeLocally(theme)
            } catch {
                print("❌ Failed to refresh from cloud: \(error)")
            }
        }
    }

    func updateNightlyNotification() {
        let context = NightlyNotificationBuilder.makeContext(
            scheduleDict: scheduleDict,
            data: data
        )

        NotificationManager.shared.scheduleNightly(
            dayCode: context.dayCode,
            firstClassName: context.firstClassName,
            firstClassTime: context.firstClassTime,
            firstClassRoom: context.firstClassRoom
        )
    }

    func applyOnboardingClassesIfNeeded(_ onboardingClasses: [ClassItem]) {
        guard !onboardingClasses.isEmpty else { return }
        guard var currentData = data else { return }

        for (index, item) in onboardingClasses.enumerated() {
            guard index < currentData.classes.count else { break }
            let name = item.name.trimmingCharacters(in: .whitespaces)
            let teacher = item.teacher.trimmingCharacters(in: .whitespaces)
            let room = item.room.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { currentData.classes[index].name = name }
            if !teacher.isEmpty { currentData.classes[index].teacher = teacher }
            if !room.isEmpty { currentData.classes[index].room = room }
        }

        data = currentData
        overwriteClassesFile(with: currentData.classes)
        saveDataForWidget()
    }

    func resetHomeDateToToday(events: [CustomEvent]) {
        let today = Date()
        selectedDate = today

        if scheduleDict != nil {
            applySelectedDate(today, events: events)
        }
    }

    func handleUserChange(_ userId: String?) {
        themeDebounceTask?.cancel()
        hasLoadedFromCloud = false
    }

    func scrollTargetForCurrentSchedule() -> Int {
        ScheduleRenderer.shared.currentClassIndex(in: scheduleLines) ?? 0
    }

    private func applyLocalData(onboardingClasses: [ClassItem]) {
        guard let localState = persistence.loadLocalSchedule(
            parseClass: ScheduleParsing.parseClass,
            parseDays: ScheduleParsing.parseDays
        ) else {
            output = "Days.txt not found in bundle."
            return
        }

        applyScheduleState(localState, overwriteClasses: false)
        applyOnboardingClassesIfNeeded(onboardingClasses)
    }

    private func syncCloudData(authManager: AuthenticationManager) {
        guard let user = authManager.user, !hasLoadedFromCloud else { return }

        Task {
            do {
                guard let days = data?.days else { return }
                let cloudState = try await persistence.loadCloudScheduleState(for: user.id, days: days)
                if !cloudState.classes.isEmpty {
                    applyScheduleState(cloudState)
                } else {
                    applyThemeState(cloudState.theme)
                }
                saveDataForWidget()
                hasLoadedFromCloud = true
            } catch {
                print("❌ Failed to load from cloud: \(error)")
            }
        }
    }

    private func saveThemeLocally(_ theme: ThemeColors) {
        persistence.saveThemeLocally(theme)
    }

    private func debouncedCloudSave(authManager: AuthenticationManager, theme: ThemeColors) {
        themeDebounceTask?.cancel()

        if let lastSavedTheme,
           lastSavedTheme.primary == theme.primary,
           lastSavedTheme.secondary == theme.secondary,
           lastSavedTheme.tertiary == theme.tertiary,
           lastSavedTheme.primaryFont == theme.primaryFont,
           lastSavedTheme.secondaryFont == theme.secondaryFont {
            return
        }

        themeDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled, authManager.user != nil {
                    saveSchedule(authManager: authManager)
                    lastSavedTheme = theme
                }
            } catch {}
        }
    }

    private func applyThemeState(_ themeState: PersistedThemeState) {
        primaryColor = Color(hex: themeState.primary)
        secondaryColor = Color(hex: themeState.secondary)
        tertiaryColor = Color(hex: themeState.tertiary)
        primaryFontChoice = themeState.primaryFontChoice
        secondaryFontChoice = themeState.secondaryFontChoice
    }

    private func applyTheme(_ theme: ThemeColors) {
        primaryColor = Color(hex: theme.primary)
        secondaryColor = Color(hex: theme.secondary)
        tertiaryColor = Color(hex: theme.tertiary)
        primaryFontChoice = theme.primaryFontChoice
        secondaryFontChoice = theme.secondaryFontChoice
    }

    private func applyScheduleState(_ scheduleState: PersistedScheduleState, overwriteClasses: Bool = true) {
        data = scheduleState.normalizedData
        applyThemeState(scheduleState.theme)
        saveThemeLocally(currentTheme)
        if overwriteClasses {
            overwriteClassesFile(with: scheduleState.normalizedData.classes)
        }
    }

    private func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let dayIndex = map[currentDay.lowercased()],
              let data,
              data.days.indices.contains(dayIndex) else { return nil }
        return dayIndex
    }

    private func parseCSV(_ csvString: String, events: [CustomEvent]) {
        guard let tempDict = CSVParser.parseScheduleCSV(csvString) else {
            output = "Failed to load schedule."
            return
        }

        scheduleDict = tempDict
        applySelectedDate(selectedDate, events: events)
        if let dictData = try? JSONEncoder().encode(tempDict) {
            SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
        }
        updateNightlyNotification()
        saveDataForWidget()
    }

    private func refreshRenderedSchedule(events: [CustomEvent]) {
        scheduleLines = ScheduleSelectionResolver.renderedLines(
            dayCode: dayCode,
            selectedDate: selectedDate,
            data: data,
            events: events
        )
    }

    private func fetchScheduleFromGoogleSheets(events: [CustomEvent]) {
        Task { await fetchWithRetry(attempt: 1, events: events) }
    }

    private func fetchScheduleFromGoogleSheetsAsync(events: [CustomEvent]) async {
        await fetchWithRetry(attempt: 1, events: events)
    }

    private func fetchWithRetry(
        attempt: Int,
        events: [CustomEvent],
        maxAttempts: Int = 10
    ) async {
        let csvURL = "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/export?format=csv&gid=0"
        guard let url = URL(string: csvURL) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let csv = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            scheduleRetryAttempt = 0
            scheduleLoadError = nil
            parseCSV(csv, events: events)
            applySelectedDate(selectedDate, events: events)
            saveDataForWidget()
        } catch {
            if attempt < maxAttempts {
                scheduleRetryAttempt = attempt
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                await fetchWithRetry(attempt: attempt + 1, events: events, maxAttempts: maxAttempts)
            } else {
                scheduleRetryAttempt = 0
                scheduleLoadError = "Could not load schedule. Close and reopen the app to try again."
            }
        }
    }

    private func saveDataForWidget() {
        WidgetManager.shared.saveData(
            scheduleDict: scheduleDict,
            data: data,
            dayCode: dayCode
        )
    }

    private func saveScheduleLinesWithEvents(events: [CustomEvent]) {
        WidgetManager.shared.saveScheduleLinesWithEvents(
            scheduleLines: scheduleLines,
            events: events,
            dayCode: dayCode,
            selectedDate: selectedDate
        )
    }

    private func updateLiveActivity() {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let dayName = getDayInfo(for: dayCode)?.name ?? dayCode
        WidgetManager.shared.updateLiveActivity(
            scheduleLines: scheduleLines,
            dayCode: dayCode,
            dayName: dayName,
            isToday: isToday
        )
    }
}
