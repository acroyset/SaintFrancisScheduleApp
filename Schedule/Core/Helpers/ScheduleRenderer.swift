//
//  ScheduleRenderer.swift
//  Schedule
//
//  Extracted from ContentView.swift
//

import Foundation
import SwiftUI
import WidgetKit

class ScheduleRenderer {
    
    // MARK: - Schedule Rendering
    static func renderWithEvents(
        data: ScheduleData,
        dayCode: String,
        selectedDate: Date,
        eventsManager: CustomEventsManager
    ) -> (scheduleLines: [ScheduleLine], output: String) {
        
        let cal = Calendar.current
        let isToday = cal.isDateInToday(selectedDate)
        
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            if !dayCode.isEmpty && dayCode != "None" {
                return ([], "Invalid day code: '\(dayCode)'. Valid codes: G1, B1, G2, B2, A1, A2, A3, A4, L1, L2, S1")
            } else {
                return ([], "Loading schedule...")
            }
        }
        
        let d = data.days[di]
        let now = Time.now()
        let nowSec = now.seconds
        
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: data.isSecondLunch)
        
        var tempLines: [(index: Int, line: ScheduleLine)] = []
        
        for i in d.names.indices {
            let nameRaw = d.names[i]
            let start = d.startTimes[i]
            let end = d.endTimes[i]
            let isCurrentClass = (start <= now && now < end) && isToday
            
            // Add passing periods for today
            if isToday {
                if i != 0 && d.endTimes[i-1] <= now && now < start {
                    let endT = start
                    let startT = d.endTimes[i-1]
                    let p = progressValue(start: startT.seconds, end: endT.seconds, now: nowSec)
                    if startT > Time(h:8, m:0, s:0) &&
                       endT < Time(h:14, m:30, s:0) &&
                       endT.seconds - startT.seconds <= 600 {
                        tempLines.append((i, ScheduleLine(
                            content: "",
                            base: "",
                            isCurrentClass: true,
                            timeRange: "\(startT.string()) to \(endT.string())",
                            className: "Passing Period",
                            startSec: startT.seconds,
                            endSec: endT.seconds,
                            progress: p
                        )))
                    }
                }
            }
            
            // Add regular classes
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room = (c.room == "N" || c.room.isEmpty) ? "" : c.room
                
                let p = progressValue(start: start.seconds, end: end.seconds, now: nowSec)
                
                tempLines.append((i, ScheduleLine(
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
                )))
            } else {
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw)))
            }
        }
        
        // Apply SECOND LUNCH override
        if shouldSwap {
            for (i, item) in tempLines.enumerated() {
                if item.line.className == "Lunch" {
                    var line = item.line
                    line.startSec = Time(h:12, m:25, s:0).seconds
                    line.endSec = Time(h:13, m:05, s:0).seconds
                    line.timeRange = "12:25 to 1:05"
                    tempLines[i].line = line
                }
                
                // Handle Brunch
                if item.line.className == "Brunch" {
                    var line = item.line
                    line.startSec = Time(h:11, m:10, s:0).seconds
                    line.endSec   = Time(h:11, m:35, s:0).seconds
                    line.timeRange = "11:10 to 11:35"
                    tempLines[i].line = line
                }

                // Swap Period 4/5 for Lunch days
                if (item.line.base.contains("$4") || item.line.base.contains("$5")) &&
                   tempLines.contains(where: { $0.line.className == "Lunch" }) {
                    var line = item.line
                    line.startSec = Time(h:11, m:00, s:0).seconds
                    line.endSec = Time(h:12, m:20, s:0).seconds
                    line.timeRange = "11:00 to 12:20"
                    tempLines[i].line = line
                }
                
                // Swap Period 4 for Brunch days
                if item.line.base.contains("$4") &&
                   tempLines.contains(where: { $0.line.className == "Brunch" }) {
                    var line = item.line
                    line.startSec = Time(h:9, m:45, s:0).seconds
                    line.endSec   = Time(h:11, m:05, s:0).seconds
                    line.timeRange = "9:45 to 11:05"
                    tempLines[i].line = line
                }
            }
        }
        
        let scheduleLines = tempLines.map { $0.line }
        
        // Check for conflicts with custom events
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: selectedDate)
        let conflicts = checkForEventConflicts(events: todaysEvents, scheduleLines: scheduleLines)
        
        if !conflicts.isEmpty{
            print("conflict")
        }
        
        return (scheduleLines, "")
    }
    
    // MARK: - Helper Methods
    private static func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let daysWithLunchPeriodG = [0, 2, 4, 5, 6, 7, 8, 9]
        let daysWithLunchPeriodB = [1, 3]
        return (isSecondLunch[0] && daysWithLunchPeriodG.contains(dayIndex)) || (isSecondLunch[1] && daysWithLunchPeriodB.contains(dayIndex))
    }
    
    private static func checkForEventConflicts(
        events: [CustomEvent],
        scheduleLines: [ScheduleLine]
    ) -> [EventConflict] {
        var allConflicts: [EventConflict] = []
        
        for event in events {
            for line in scheduleLines {
                if event.conflictsWith(line) {
                    let severity = calculateConflictSeverity(event: event, scheduleLine: line)
                    allConflicts.append(EventConflict(
                        event: event,
                        conflictingScheduleLine: line,
                        severity: severity
                    ))
                }
            }
        }
        
        return allConflicts
    }
    
    private static func calculateConflictSeverity(
        event: CustomEvent,
        scheduleLine: ScheduleLine
    ) -> ConflictSeverity {
        guard let classStart = scheduleLine.startSec,
              let classEnd = scheduleLine.endSec else { return .minor }
        
        let eventStart = event.startTime.seconds
        let eventEnd = event.endTime.seconds
        
        let overlapStart = max(eventStart, classStart)
        let overlapEnd = min(eventEnd, classEnd)
        let overlapDuration = overlapEnd - overlapStart
        
        if overlapDuration >= (classEnd - classStart) * 8 / 10 {
            return .complete
        } else if overlapDuration >= 900 {
            return .major
        } else {
            return .minor
        }
    }
    
    // MARK: - Schedule Line Saving
    static func saveScheduleLinesWithEvents(
        scheduleLines: [ScheduleLine],
        dayCode: String,
        selectedDate: Date,
        eventsManager: CustomEventsManager
    ) {
        var allItems: [ScheduleLine] = scheduleLines
        
        // Convert events to ScheduleLine format for widget compatibility
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: selectedDate)
        for event in todaysEvents where event.isEnabled {
            let eventLine = ScheduleLine(
                content: "",
                base: "",
                isCurrentClass: false,
                timeRange: "\(event.startTime.string()) to \(event.endTime.string())",
                className: "\(event.title)",
                teacher: event.location,
                room: event.note,
                startSec: event.startTime.seconds,
                endSec: event.endTime.seconds,
                progress: nil
            )
            allItems.append(eventLine)
        }
        
        // Sort by start time
        allItems.sort { first, second in
            guard let firstStart = first.startSec, let secondStart = second.startSec else {
                return false
            }
            return firstStart < secondStart
        }
        
        do {
            let data = try JSONEncoder().encode(allItems)
            SharedGroup.defaults.set(data, forKey: SharedGroup.key)
            SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            
            let eventsData = try JSONEncoder().encode(eventsManager.events)
            SharedGroup.defaults.set(eventsData, forKey: "CustomEvents")
            
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        } catch {
            print("❌ Encoding failed:", error)
        }
    }
}
