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
    
    return ScheduleData(classes: classes, days: days, isSecondLunch: isSecondLunch)
}

func getKeyForDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd-yy"
    return formatter.string(from: date)
}

func loadScheduleLines() -> [ScheduleLine] {
    guard let data = UserDefaults(suiteName: SharedGroup.id)?
                        .data(forKey: SharedGroup.key) else { return [] }
    return (try? JSONDecoder().decode([ScheduleLine].self, from: data)) ?? []
}

func loadThemeColors() -> ThemeColors? {
    guard let data = SharedGroup.defaults.data(forKey: "ThemeColors") else { return nil }
    return try? JSONDecoder().decode(ThemeColors.self, from: data)
}
