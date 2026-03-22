//
//  WidgetManager.swift
//  Schedule
//
//  Owns all widget and Live Activity coordination that previously
//  lived inline in ContentView.
//

import SwiftUI
import WidgetKit

@MainActor
final class WidgetManager: ObservableObject {

    static let shared = WidgetManager()
    private init() {}

    // MARK: - Save data for widget

    func saveData(
        scheduleDict: [String: [String]]?,
        data: ScheduleData?,
        dayCode: String
    ) {
        if let scheduleDict,
           let dictData = try? JSONEncoder().encode(scheduleDict) {
            SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
        }

        guard let data else { return }

        if let classesData = try? JSONEncoder().encode(data.classes) {
            SharedGroup.defaults.set(classesData, forKey: "ScheduleClasses")
        }
        if let daysData = try? JSONEncoder().encode(data.days) {
            SharedGroup.defaults.set(daysData, forKey: "ScheduleDays")
        }

        SharedGroup.defaults.set(data.isSecondLunch, forKey: "IsSecondLunch")
        SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
        SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")

        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
    }

    // MARK: - Save schedule lines + events

    func saveScheduleLinesWithEvents(
        scheduleLines: [ScheduleLine],
        events: [CustomEvent],
        dayCode: String,
        selectedDate: Date
    ) {
        let todaysEvents = events.filter { $0.appliesTo(dayCode: dayCode, date: selectedDate) }

        var allItems: [ScheduleLine] = scheduleLines
        for event in todaysEvents {
            allItems.append(ScheduleLine(
                content: "",
                base: "",
                isCurrentClass: false,
                timeRange: "\(event.startTime.string()) to \(event.endTime.string())",
                className: event.title,
                teacher: event.location,
                room: event.note,
                startSec: event.startTime.seconds,
                endSec: event.endTime.seconds,
                progress: nil
            ))
        }
        allItems.sort { ($0.startSec ?? 0) < ($1.startSec ?? 0) }

        do {
            let linesData  = try JSONEncoder().encode(allItems)
            let eventsData = try JSONEncoder().encode(events)
            SharedGroup.defaults.set(linesData,  forKey: SharedGroup.key)
            SharedGroup.defaults.set(eventsData, forKey: "CustomEvents")
            SharedGroup.defaults.set(Date(),     forKey: "LastAppDataUpdate")
            SharedGroup.defaults.set(dayCode,    forKey: "CurrentDayCode")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        } catch {
            print("❌ WidgetManager encoding failed:", error)
        }
    }

    // MARK: - Live Activity

    func updateLiveActivity(
        scheduleLines: [ScheduleLine],
        dayCode: String,
        dayName: String,
        isToday: Bool
    ) {
        guard isToday else {
            LiveActivityManager.shared.endActivity()
            return
        }
        LiveActivityManager.shared.update(
            scheduleLines: scheduleLines,
            dayCode: dayCode,
            dayName: dayName
        )
    }

    // MARK: - Widget refresh request

    func handleRefreshRequestIfNeeded(refreshAction: @escaping () async -> Void) {
        guard SharedGroup.defaults.bool(forKey: "WidgetRequestsUpdate") else { return }
        SharedGroup.defaults.set(false, forKey: "WidgetRequestsUpdate")
        Task { await refreshAction() }
    }

    // MARK: - Theme

    func saveTheme(_ theme: ThemeColors) {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        SharedGroup.defaults.set(data, forKey: "ThemeColors")
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "DayTypeWidget")
    }
}
