//
//  HomeViewModel.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published var showCalendarGrid = false
    @Published var scrollTarget: Int?
    @Published var dayCode = ""
    @Published var note = ""
    @Published var scheduleLines: [ScheduleLine] = []
    
    private let scheduleData: ScheduleData
    private let scheduleDict: [String: [String]]?
    
    init(scheduleData: ScheduleData, scheduleDict: [String: [String]]?) {
        self.scheduleData = scheduleData
        self.scheduleDict = scheduleDict
    }
    
    func applySelectedDate(_ date: Date) {
        selectedDate = date
        let key = getKeyToday()
        
        if let day = scheduleDict?[key] {
            dayCode = day[0]
            note = day[1]
            
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            renderSchedule()
            
            DispatchQueue.main.async {
                self.scrollTarget = self.currentClassIndex() ?? 0
            }
        } else {
            dayCode = "None"
            SharedGroup.defaults.set("", forKey: "CurrentDayCode")
        }
    }
    
    private func renderSchedule() {
        // Schedule rendering logic would go here
        // This is a simplified version - you'd move the full logic from ContentView
    }
    
    private func currentClassIndex() -> Int? {
        if let i = scheduleLines.firstIndex(where: { $0.isCurrentClass && !$0.timeRange.isEmpty }) {
            return i
        }
        return scheduleLines.firstIndex(where: { $0.isCurrentClass }) ??
               scheduleLines.firstIndex(where: { !$0.timeRange.isEmpty })
    }
    
    private func getKeyToday() -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.timeZone = .current
        f.dateFormat = "MM-dd-yy"
        return f.string(from: selectedDate)
    }
}
