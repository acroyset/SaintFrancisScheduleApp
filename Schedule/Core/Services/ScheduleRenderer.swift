//
//  ScheduleRenderer.swift
//  Schedule
//
//  Created by Andreas Royset on 3/22/26.
//
//
//  Owns all schedule-rendering logic that previously lived inline
//  in ContentView — turning raw ScheduleData + events into the
//  sorted, progress-annotated [ScheduleLine] array the UI displays.
//

import SwiftUI

@MainActor
final class ScheduleRenderer {

    static let shared = ScheduleRenderer()
    private init() {}

    // MARK: - Public

    /// Builds the full sorted [ScheduleLine] array for the given day,
    /// including passing periods and real-time progress values.
    func render(
        dayCode: String,
        selectedDate: Date,
        data: ScheduleData,
        events: [CustomEvent],
        specialScheduleCode: String = ""
    ) -> [ScheduleLine] {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()] else {
            return []
        }

        let d: Day
        if dayCode.caseInsensitiveCompare("s1") == .orderedSame,
           let specialSchedule = SpecialSchedule(code: specialScheduleCode) {
            d = specialSchedule.day
        } else {
            guard data.days.indices.contains(di) else { return [] }
            d = data.days[di]
        }

        let cal     = Calendar.current
        let isToday = cal.isDateInToday(selectedDate)
        let now     = Time.now()
        let nowSec  = now.seconds
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: data.isSecondLunch)

        var tempLines: [(index: Int, line: ScheduleLine)] = []

        // Build raw lines from the day definition
        for i in d.names.indices {
            let nameRaw = d.names[i]
            let start   = d.startTimes[i]
            let end     = d.endTimes[i]

            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c       = data.classes[idx - 1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room    = (c.room    == "N" || c.room.isEmpty)    ? "" : c.room
                tempLines.append((i, ScheduleLine(
                    content: "", base: nameRaw, isCurrentClass: false,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: c.name, teacher: teacher, room: room,
                    startSec: start.seconds, endSec: end.seconds, progress: nil
                )))
            } else {
                tempLines.append((i, ScheduleLine(
                    content: "", base: nameRaw, isCurrentClass: false,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw,
                    startSec: start.seconds, endSec: end.seconds
                )))
            }
        }

        // Apply second-lunch time overrides
        if shouldSwap {
            for (i, item) in tempLines.enumerated() {
                if item.line.className == "Lunch" {
                    var line = item.line
                    line.startSec  = Time(h: 12, m: 25, s: 0).seconds
                    line.endSec    = Time(h: 13, m:  5, s: 0).seconds
                    line.timeRange = "12:25 to 1:05"
                    tempLines[i].line = line
                }
                if item.line.className == "Brunch" {
                    var line = item.line
                    line.startSec  = Time(h: 11, m: 10, s: 0).seconds
                    line.endSec    = Time(h: 11, m: 35, s: 0).seconds
                    line.timeRange = "11:10 to 11:35"
                    tempLines[i].line = line
                }
                if (item.line.base.contains("$4") || item.line.base.contains("$5")) &&
                    tempLines.contains(where: { $0.line.className == "Lunch" }) {
                    var line = item.line
                    line.startSec  = Time(h: 11, m:  0, s: 0).seconds
                    line.endSec    = Time(h: 12, m: 20, s: 0).seconds
                    line.timeRange = "11:00 to 12:20"
                    tempLines[i].line = line
                }
                if item.line.base.contains("$4") &&
                    tempLines.contains(where: { $0.line.className == "Brunch" }) {
                    var line = item.line
                    line.startSec  = Time(h: 9, m: 45, s: 0).seconds
                    line.endSec    = Time(h: 11, m: 5, s: 0).seconds
                    line.timeRange = "9:45 to 11:05"
                    tempLines[i].line = line
                }
            }
        }

        // Sort by start time
        tempLines.sort { ($0.line.startSec ?? 0) < ($1.line.startSec ?? 0) }

        // Annotate current class + progress
        for (i, item) in tempLines.enumerated() {
            var line = item.line
            if let startSec = line.startSec, let endSec = line.endSec {
                line.isCurrentClass = (startSec <= nowSec && nowSec < endSec) && isToday
                line.progress       = progressValue(start: startSec, end: endSec, now: nowSec)
                tempLines[i].line   = line
            }
        }

        // Insert passing periods for today only
        if isToday {
            var passingSections: [(index: Int, line: ScheduleLine)] = []
            for i in 1..<tempLines.count {
                let prevEnd   = tempLines[i - 1].line.endSec   ?? 0
                let currStart = tempLines[i].line.startSec ?? 0
                let gap       = currStart - prevEnd
                let isCurrent = prevEnd <= nowSec && nowSec < currStart
                if isCurrent && gap > 0 && gap <= 600 {
                    let p = progressValue(start: prevEnd, end: currStart, now: nowSec)
                    passingSections.append((i, ScheduleLine(
                        content: "", base: "", isCurrentClass: true,
                        timeRange: "\(Time(seconds: prevEnd).string()) to \(Time(seconds: currStart).string())",
                        className: "Passing Period",
                        startSec: prevEnd, endSec: currStart, progress: p
                    )))
                }
            }
            for section in passingSections.reversed() {
                tempLines.insert(section, at: section.index)
            }
        }

        return tempLines.map { $0.line }
    }

    // MARK: - Current class index (for scroll targeting)

    /// Returns the index to scroll to — current class, or first upcoming,
    /// or first item with a time range.
    func currentClassIndex(in lines: [ScheduleLine]) -> Int? {
        if let i = lines.firstIndex(where: { $0.isCurrentClass && !$0.timeRange.isEmpty }) {
            return i
        }
        return lines.firstIndex(where: { $0.isCurrentClass })
            ?? lines.firstIndex(where: { !$0.timeRange.isEmpty })
    }

    /// Updates only time-sensitive flags and progress values. Static schedule
    /// rendering, persistence, widgets, and Live Activities stay off the
    /// one-second UI ticker.
    func refreshingProgress(
        in lines: [ScheduleLine],
        selectedDate: Date,
        nowSeconds: Int = Time.now().seconds
    ) -> [ScheduleLine] {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let existingPassingPeriod = lines.first(where: { $0.className == "Passing Period" })
        var refreshed = lines.filter { $0.className != "Passing Period" }

        for index in refreshed.indices {
            guard let start = refreshed[index].startSec,
                  let end = refreshed[index].endSec else { continue }
            refreshed[index].isCurrentClass = isToday && start <= nowSeconds && nowSeconds < end
            refreshed[index].progress = progressValue(start: start, end: end, now: nowSeconds)
        }

        guard isToday, refreshed.count > 1 else { return refreshed }

        for index in 1..<refreshed.count {
            guard let previousEnd = refreshed[index - 1].endSec,
                  let currentStart = refreshed[index].startSec else { continue }
            let gap = currentStart - previousEnd
            guard gap > 0, gap <= 600,
                  previousEnd <= nowSeconds, nowSeconds < currentStart else { continue }

            var passingPeriod: ScheduleLine
            if var existingPassingPeriod,
               existingPassingPeriod.startSec == previousEnd,
               existingPassingPeriod.endSec == currentStart {
                existingPassingPeriod.isCurrentClass = true
                existingPassingPeriod.progress = progressValue(
                    start: previousEnd,
                    end: currentStart,
                    now: nowSeconds
                )
                passingPeriod = existingPassingPeriod
            } else {
                passingPeriod = ScheduleLine(
                    content: "",
                    base: "",
                    isCurrentClass: true,
                    timeRange: "\(Time(seconds: previousEnd).string()) to \(Time(seconds: currentStart).string())",
                    className: "Passing Period",
                    startSec: previousEnd,
                    endSec: currentStart,
                    progress: progressValue(start: previousEnd, end: currentStart, now: nowSeconds)
                )
            }
            refreshed.insert(passingPeriod, at: index)
            break
        }

        return refreshed
    }

    // MARK: - Private helpers

    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let goldDays  = [0, 2, 4, 5, 6, 7, 8, 9]
        let brownDays = [1, 3]
        let goldSecondLunch = isSecondLunch.indices.contains(0) ? isSecondLunch[0] : false
        let brownSecondLunch = isSecondLunch.indices.contains(1) ? isSecondLunch[1] : false
        return (goldSecondLunch && goldDays.contains(dayIndex))
            || (brownSecondLunch && brownDays.contains(dayIndex))
    }
}
