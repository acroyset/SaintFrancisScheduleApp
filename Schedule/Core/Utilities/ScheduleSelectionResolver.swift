//
//  ScheduleSelectionResolver.swift
//  Schedule
//

import Foundation

struct ResolvedScheduleSelection {
    let dayCode: String
    let note: String
    let output: String
    let scheduleLines: [ScheduleLine]
    let scrollTarget: Int?
}

enum ScheduleSelectionResolver {
    @MainActor
    static func resolve(
        selectedDate: Date,
        scheduleDict: [String: [String]]?,
        data: ScheduleData?,
        events: [CustomEvent]
    ) -> ResolvedScheduleSelection {
        let key = scheduleKey(for: selectedDate)

        guard let day = scheduleDict?[key] else {
            let scheduleLines = renderedLines(
                dayCode: "None",
                selectedDate: selectedDate,
                data: data,
                events: events
            )

            return ResolvedScheduleSelection(
                dayCode: "None",
                note: "",
                output: "No schedule found for \(key)",
                scheduleLines: scheduleLines,
                scrollTarget: ScheduleRenderer.shared.currentClassIndex(in: scheduleLines)
            )
        }

        let dayCode = day[0]
        let note = day.count > 1 ? day[1] : ""
        let scheduleLines = renderedLines(
            dayCode: dayCode,
            selectedDate: selectedDate,
            data: data,
            events: events
        )

        return ResolvedScheduleSelection(
            dayCode: dayCode,
            note: note,
            output: "",
            scheduleLines: scheduleLines,
            scrollTarget: ScheduleRenderer.shared.currentClassIndex(in: scheduleLines)
        )
    }

    @MainActor
    static func renderedLines(
        dayCode: String,
        selectedDate: Date,
        data: ScheduleData?,
        events: [CustomEvent]
    ) -> [ScheduleLine] {
        ScheduleRenderer.shared.render(
            dayCode: dayCode,
            selectedDate: selectedDate,
            data: data ?? ScheduleData(classes: [], days: []),
            events: events
        )
    }

    nonisolated
    static func scheduleKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd-yy"
        return formatter.string(from: date)
    }
}
