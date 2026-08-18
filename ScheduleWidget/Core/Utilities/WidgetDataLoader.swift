import WidgetKit
import SwiftUI

func loadScheduleDict() -> [String: [String]]? {
    guard let data = SharedGroup.defaults.data(forKey: "ScheduleDict") else {
        return nil
    }
    return try? JSONDecoder().decode([String: [String]].self, from: data)
}

func loadScheduleData() -> ScheduleData? {
    // Try to load from shared defaults (saved by main app)
    guard let classesData = SharedGroup.defaults.data(forKey: "ScheduleClasses"),
          let daysData = SharedGroup.defaults.data(forKey: "ScheduleDays") else {
        return nil
    }
    
    guard let classes = try? JSONDecoder().decode([ClassItem].self, from: classesData),
          let days = try? JSONDecoder().decode([Day].self, from: daysData) else {
        return nil
    }
    
    let isSecondLunch = (SharedGroup.defaults.array(forKey: "IsSecondLunch") as? [Bool]) ?? [false, false]
    
    return ScheduleData(classes: classes, days: days, isSecondLunch: isSecondLunch).normalized()
}

func getKeyForDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd-yy"
    return formatter.string(from: date)
}

func loadThemeColors() -> ThemeColors? {
    guard let data = SharedGroup.defaults.data(forKey: "ThemeColors") else { return nil }
    return try? JSONDecoder().decode(ThemeColors.self, from: data)
}

func widgetDayCode(for date: Date, scheduleDict: [String: [String]]) -> String? {
    scheduleDict[getKeyForDate(date)]?.first
}

func widgetDayHasClasses(on date: Date, scheduleDict: [String: [String]], data: ScheduleData) -> Bool {
    guard let dayInfo = scheduleDict[getKeyForDate(date)],
          let dayCode = dayInfo.first else {
        return false
    }
    let specialScheduleCode = dayInfo.count > 2 ? dayInfo[2] : ""
    return widgetDayHasClasses(
        dayCode: dayCode,
        specialScheduleCode: specialScheduleCode,
        data: data
    )
}

func widgetDayHasClasses(
    dayCode: String,
    specialScheduleCode: String = "",
    data: ScheduleData
) -> Bool {
    guard let day = resolvedWidgetDay(
        dayCode: dayCode,
        specialScheduleCode: specialScheduleCode,
        data: data
    ) else {
        return false
    }

    return !day.names.isEmpty && !day.startTimes.isEmpty
}

func resolvedWidgetDay(
    dayCode: String,
    specialScheduleCode: String = "",
    data: ScheduleData
) -> Day? {
    let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]

    guard let index = map[dayCode.lowercased()],
          data.days.indices.contains(index) else {
        return nil
    }

    if dayCode.caseInsensitiveCompare("s1") == .orderedSame,
       let specialSchedule = SpecialSchedule(code: specialScheduleCode) {
        return specialSchedule.day
    }

    return data.days[index]
}

func nextWidgetClassDate(after date: Date, scheduleDict: [String: [String]], data: ScheduleData) -> Date? {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: date)

    for offset in 1...60 {
        guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
        if widgetDayHasClasses(on: candidate, scheduleDict: scheduleDict, data: data) {
            return candidate
        }
    }

    return nil
}

func formattedWidgetNextClassText(for date: Date, relativeTo referenceDate: Date) -> String {
    let calendar = Calendar.current
    let referenceStart = calendar.startOfDay(for: referenceDate)
    let targetStart = calendar.startOfDay(for: date)
    let dayDistance = calendar.dateComponents([.day], from: referenceStart, to: targetStart).day ?? 0

    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = dayDistance <= 6 ? "EEE MMM d" : "MMM d"

    if dayDistance == 1 {
        return "Next class tomorrow \(formatter.string(from: date))"
    }

    return "Next class on \(formatter.string(from: date))"
}
