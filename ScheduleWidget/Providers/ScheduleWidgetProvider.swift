//
//  ScheduleWidgetProvider.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import WidgetKit
import SwiftUI


struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), lines: [], dayCode: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let (lines, dayCode) = loadTodaysSchedule()
        completion(SimpleEntry(date: Date(), lines: lines, dayCode: dayCode))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        
        // Get today's schedule
        let (lines, dayCode) = loadTodaysSchedule()
        
        var entries: [SimpleEntry] = []
        let nowSec = secondsSinceMidnight(now)
        
        entries.append(SimpleEntry(date: now, lines: lines, dayCode: dayCode))
        
        let today = cal.startOfDay(for: now)
        
        for line in lines {
            guard let startSec = line.startSec, let endSec = line.endSec else { continue }
            
            // Class start
            if startSec > nowSec {
                let startTime = today.addingTimeInterval(TimeInterval(startSec))
                entries.append(SimpleEntry(date: startTime, lines: lines, dayCode: dayCode))
            }
            
            // Class end
            if endSec > nowSec {
                let endTime = today.addingTimeInterval(TimeInterval(endSec))
                entries.append(SimpleEntry(date: endTime, lines: lines, dayCode: dayCode))
            }
            
            // During current class: add update every 1 minutes
            if nowSec >= startSec && nowSec < endSec {
                var nextMin = ((nowSec / 60) + 1) * 60 // Next 1-min mark
                while nextMin < endSec {
                    let updateTime = today.addingTimeInterval(TimeInterval(nextMin))
                    if updateTime > now {
                        entries.append(SimpleEntry(date: updateTime, lines: lines, dayCode: dayCode))
                    }
                    nextMin += 60 // Every 1 minutes
                }
            }
        }
        
        // 3. Remove duplicates and sort
        let uniqueEntries = Dictionary(grouping: entries) { $0.date }
            .map { $0.value.first! }
            .sorted { $0.date < $1.date }
        
        entries = uniqueEntries
        
        // 4. Determine next major refresh (midnight for new day)
        var nextMajorUpdate = cal.startOfDay(for: now)
        nextMajorUpdate = cal.date(byAdding: .day, value: 1, to: nextMajorUpdate)!
        
        // Also consider next class event if sooner
        if let nextClassTime = entries.dropFirst().first?.date,
           nextClassTime < nextMajorUpdate {
            nextMajorUpdate = nextClassTime
        }
        
        // Create timeline with smart refresh policy
        let timeline = Timeline(
            entries: entries.isEmpty ? [SimpleEntry(date: now, lines: lines, dayCode: dayCode)] : entries,
            policy: .after(nextMajorUpdate)
        )
        
        completion(timeline)
    }
    
    private func loadTodaysSchedule() -> ([ScheduleLine], String) {
        let now = Date()
        
        // 1. Get the schedule dictionary from shared storage
        guard let scheduleDict = loadScheduleDict() else {
            print("❌ Widget: Failed to load schedule dictionary")
            return ([], "")
        }
        
        // 2. Get today's date key
        let dateKey = getKeyForDate(now)
        
        // 3. Get today's day code
        guard let dayInfo = scheduleDict[dateKey],
              dayInfo.count >= 1 else {
            print("❌ Widget: No schedule for \(dateKey)")
            return ([], "")
        }
        
        let dayCode = dayInfo[0]
        
        // 4. Load the class data
        guard let data = loadScheduleData() else {
            print("❌ Widget: Failed to load schedule data")
            return ([], dayCode)
        }
        
        // 5. Generate schedule lines for today
        let lines = generateScheduleLines(for: dayCode, data: data, date: now)
        
        return (lines, dayCode)
    }
    
    private func generateScheduleLines(for dayCode: String, data: ScheduleData, date: Date) -> [ScheduleLine] {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            return []
        }
        
        let day = data.days[di]
        let now = Time.now()
        let nowSec = now.seconds
        
        // Check if we need to swap lunch and period 4/5
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: data.isSecondLunch)
        
        var tempLines: [(index: Int, line: ScheduleLine)] = []
        
        for i in day.names.indices {
            let nameRaw = day.names[i]
            let start = day.startTimes[i]
            let end = day.endTimes[i]
            
            // Handle class references ($1, $2, etc.)
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room = (c.room == "N" || c.room.isEmpty) ? "" : c.room
                
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: false,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: c.name,
                    teacher: teacher,
                    room: room,
                    startSec: start.seconds,
                    endSec: end.seconds,
                    progress: nil
                )))
            } else {
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: false,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw,
                    startSec: start.seconds,
                    endSec: end.seconds
                )))
            }
        }
        
        // Apply second lunch override
        if shouldSwap {
            for (i, item) in tempLines.enumerated() {
                if item.line.className == "Lunch" {
                    var line = item.line
                    line.startSec = Time(h:12, m:25, s:0).seconds
                    line.endSec   = Time(h:13, m:05, s:0).seconds
                    line.timeRange = "12:25 to 1:05"
                    tempLines[i].line = line
                }
                
                // Handle Brunch
                if item.line.className == "Brunch" {
                    var line = item.line
                    line.startSec = Time(h:11, m:10, s:0).seconds
                    line.endSec = Time(h:11, m:35, s:0).seconds
                    line.timeRange = "11:10 to 11:35"
                    tempLines[i].line = line
                }
                
                // Swap Period 4/5 for Lunch days
                if (item.line.base.contains("$4") || item.line.base.contains("$5")) &&
                   tempLines.contains(where: { $0.line.className == "Lunch" }) {
                    var line = item.line
                    line.startSec = Time(h:11, m:00, s:0).seconds
                    line.endSec   = Time(h:12, m:20, s:0).seconds
                    line.timeRange = "11:00 to 12:20"
                    tempLines[i].line = line
                }
                
                // Swap Period 4 for Brunch days
                if item.line.base.contains("$4") &&
                   tempLines.contains(where: { $0.line.className == "Brunch" }) {
                    var line = item.line
                    line.startSec = Time(h:9, m:45, s:0).seconds
                    line.endSec = Time(h:11, m:05, s:0).seconds
                    line.timeRange = "9:45 to 11:05"
                    tempLines[i].line = line
                }
            }
        }
        
        let isToday = Calendar.current.isDateInToday(date)
        
        // Recalculate isCurrentClass with updated times
        for (i, item) in tempLines.enumerated() {
            var line = item.line
            if let startSec = line.startSec, let endSec = line.endSec {
                line.isCurrentClass = (startSec <= nowSec && nowSec < endSec) && isToday
                line.progress = progressValue(start: startSec, end: endSec, now: nowSec)
                tempLines[i].line = line
            }
        }
        
        // Sort tempLines by start time after swapping
        tempLines.sort { first, second in
            guard let firstStart = first.line.startSec, let secondStart = second.line.startSec else {
                return false
            }
            return firstStart < secondStart
        }
        
        // Add passing periods after times are finalized
        if isToday {
            var passingSections: [(index: Int, line: ScheduleLine)] = []
            for i in 1..<tempLines.count {
                let prevEnd = tempLines[i-1].line.endSec ?? 0
                let currStart = tempLines[i].line.startSec ?? 0
                
                // Check if there's a gap between classes of 10 minutes or less
                let gapDuration = currStart - prevEnd
                if gapDuration > 0 && gapDuration <= 600 {
                    let isCurrentPassing = (prevEnd <= nowSec && nowSec < currStart)
                    let p = progressValue(start: prevEnd, end: currStart, now: nowSec)
                    
                    if isCurrentPassing{
                        passingSections.append((i, ScheduleLine(
                            content: "",
                            base: "",
                            isCurrentClass: true,
                            timeRange: "\(Time(seconds: prevEnd).string()) to \(Time(seconds: currStart).string())",
                            className: "Passing Period",
                            startSec: prevEnd,
                            endSec: currStart,
                            progress: p
                        )))
                    }
                }
            }
            
            // Insert passing periods in reverse order to maintain indices
            for section in passingSections.reversed() {
                tempLines.insert(section, at: section.index)
            }
        }
        
        return tempLines.map { $0.line }
    }
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let daysWithLunchPeriodG = [0, 2, 4, 5, 6, 7, 8, 9]
        let daysWithLunchPeriodB = [1, 3]
        return (isSecondLunch[0] && daysWithLunchPeriodG.contains(dayIndex)) || (isSecondLunch[1] && daysWithLunchPeriodB.contains(dayIndex))
    }
}
