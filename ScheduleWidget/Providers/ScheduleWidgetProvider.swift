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
            
            // During current class: add update every 5 minutes
            if nowSec >= startSec && nowSec < endSec {
                var nextMin = ((nowSec / 300) + 1) * 300 // Next 5-min mark
                while nextMin < endSec {
                    let updateTime = today.addingTimeInterval(TimeInterval(nextMin))
                    if updateTime > now {
                        entries.append(SimpleEntry(date: updateTime, lines: lines, dayCode: dayCode))
                    }
                    nextMin += 300 // Every 5 minutes
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
        
        var lines: [ScheduleLine] = []
        
        for i in day.names.indices {
            let nameRaw = day.names[i]
            var start = day.startTimes[i]
            var end = day.endTimes[i]
            
            // Apply second lunch override
            if shouldSwap {
                if nameRaw == "Lunch" {
                    start = Time(h: 12, m: 25, s: 0)
                    end = Time(h: 13, m: 5, s: 0)
                } else if nameRaw.contains("$4") || nameRaw.contains("$5") ||
                          nameRaw.contains("Period 4") || nameRaw.contains("Period 5") {
                    start = Time(h: 11, m: 0, s: 0)
                    end = Time(h: 12, m: 20, s: 0)
                }
            }
            
            let isCurrentClass = (start <= now && now < end) && Calendar.current.isDateInToday(date)
            
            // Handle class references ($1, $2, etc.)
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room = (c.room == "N" || c.room.isEmpty) ? "" : c.room
                
                let p = progressValue(start: start.seconds, end: end.seconds, now: nowSec)
                
                lines.append(ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: c.name,
                    teacher: teacher,
                    room: room,
                    startSec: start.seconds,
                    endSec: end.seconds,
                    progress: p
                ))
            } else {
                lines.append(ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw,
                    startSec: start.seconds,
                    endSec: end.seconds
                ))
            }
        }
        
        return lines
    }
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: Bool) -> Bool {
        let daysWithLunchPeriod = [0, 1, 2, 3, 4, 5]
        return isSecondLunch && daysWithLunchPeriod.contains(dayIndex)
    }
}
