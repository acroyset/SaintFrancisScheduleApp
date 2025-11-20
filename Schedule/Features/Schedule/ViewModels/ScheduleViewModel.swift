//
//  ScheduleViewModel.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI
import Combine

@MainActor
class ScheduleViewModel: ObservableObject {
    @Published var scheduleLines: [ScheduleLine] = []
    
    private let scheduleData: ScheduleData
    private let eventsManager: CustomEventsManager
    
    init(scheduleData: ScheduleData, eventsManager: CustomEventsManager = CustomEventsManager()) {
        self.scheduleData = scheduleData
        self.eventsManager = eventsManager
    }
    
    func renderSchedule(for dayCode: String, date: Date, isToday: Bool) {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()], scheduleData.days.indices.contains(di) else {
            scheduleLines = []
            return
        }
        
        let d = scheduleData.days[di]
        let now = Time.now()
        let nowSec = now.seconds
        
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: scheduleData.isSecondLunch)
        
        var tempLines: [(index: Int, line: ScheduleLine)] = []
        
        for i in d.names.indices {
            let nameRaw = d.names[i]
            let start = d.startTimes[i]
            let end = d.endTimes[i]
            let isCurrentClass = (start <= now && now < end) && isToday
            
            // Add passing periods for today
            if isToday && i != 0 && d.endTimes[i-1] <= now && now < start {
                let endT = start
                let startT = d.endTimes[i-1]
                let p = progressValue(start: startT.seconds, end: endT.seconds, now: nowSec)
                if startT > Time(h:8, m:0, s:0) && endT < Time(h:14, m:30, s:0) && endT.seconds - startT.seconds <= 600 {
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
            
            // Add regular classes
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...scheduleData.classes.count).contains(idx) {
                let c = scheduleData.classes[idx-1]
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
        
        // Apply second lunch override
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
                    line.endSec = Time(h:11, m:35, s:0).seconds
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
                    line.endSec = Time(h:11, m:05, s:0).seconds
                    line.timeRange = "9:45 to 11:05"
                    tempLines[i].line = line
                }
            }
        }
        
        scheduleLines = tempLines.map { $0.line }
    }
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let daysWithLunchPeriodG = [0, 2, 4, 5, 6, 7, 8, 9]
        let daysWithLunchPeriodB = [1, 3]
        return (isSecondLunch[0] && daysWithLunchPeriodG.contains(dayIndex)) || (isSecondLunch[1] && daysWithLunchPeriodB.contains(dayIndex))
    }
}
