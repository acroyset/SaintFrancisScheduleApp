//
//  DateNavigationHelper.swift
//  Schedule
//
//  Extracted from ContentView.swift
//

import Foundation

class DateNavigationHelper {
    
    // MARK: - Date Navigation
    static func applySelectedDate(
        _ date: Date,
        scheduleDict: [String: [String]]?,
        completion: @escaping (String, String) -> Void
    ) {
        let key = getKeyToday(for: date)
        
        if let day = scheduleDict?[key] {
            let dayCode = day[0]
            let note = day[1]
            
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            completion(dayCode, note)
        } else {
            SharedGroup.defaults.set("", forKey: "CurrentDayCode")
            completion("None", "")
        }
    }
    
    static func getKeyToday(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.timeZone = .current
        f.dateFormat = "MM-dd-yy"
        return f.string(from: date)
    }
    
    static func currentClassIndex(in scheduleLines: [ScheduleLine]) -> Int? {
        if let i = scheduleLines.firstIndex(where: { $0.isCurrentClass && !$0.timeRange.isEmpty }) {
            return i
        }
        return scheduleLines.firstIndex(where: { $0.isCurrentClass }) ??
               scheduleLines.firstIndex(where: { !$0.timeRange.isEmpty })
    }
    
    // MARK: - Day Info
    static func getDayInfo(for currentDay: String, data: ScheduleData?) -> Day? {
        guard let di = getDayNumber(for: currentDay),
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return data.days[di]
    }
    
    static func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        return map[currentDay.lowercased()]
    }
}
