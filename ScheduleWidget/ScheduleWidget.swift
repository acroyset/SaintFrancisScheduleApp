// Enhanced ScheduleWidget.swift with Auto-updating Schedule
import WidgetKit
import SwiftUI



// MARK: - Data Loading Functions

private func loadScheduleDict() -> [String: [String]]? {
    guard let data = SharedGroup.defaults.data(forKey: "ScheduleDict") else {
        return nil
    }
    return try? JSONDecoder().decode([String: [String]].self, from: data)
}

private func loadScheduleData() -> ScheduleData? {
    // Try to load from shared defaults (saved by main app)
    guard let classesData = SharedGroup.defaults.data(forKey: "ScheduleClasses"),
          let daysData = SharedGroup.defaults.data(forKey: "ScheduleDays") else {
        return nil
    }
    
    guard let classes = try? JSONDecoder().decode([ClassItem].self, from: classesData),
          let days = try? JSONDecoder().decode([Day].self, from: daysData) else {
        return nil
    }
    
    let isSecondLunch = SharedGroup.defaults.bool(forKey: "IsSecondLunch")
    
    return ScheduleData(classes: classes, days: days, isSecondLunch: isSecondLunch)
}

private func getKeyForDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd-yy"
    return formatter.string(from: date)
}

// MARK: - Row View


// MARK: - Helper Functions
private func loadScheduleLines() -> [ScheduleLine] {
    guard let data = UserDefaults(suiteName: SharedGroup.id)?
                        .data(forKey: SharedGroup.key) else { return [] }
    return (try? JSONDecoder().decode([ScheduleLine].self, from: data)) ?? []
}



extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var int: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&int)

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 8:
            r = Double((int & 0xFF000000) >> 24) / 255
            g = Double((int & 0x00FF0000) >> 16) / 255
            b = Double((int & 0x0000FF00) >> 8) / 255
            a = Double(int & 0x000000FF) / 255
        case 6:
            r = Double((int & 0xFF0000) >> 16) / 255
            g = Double((int & 0x00FF00) >> 8) / 255
            b = Double(int & 0x0000FF) / 255
            a = 1.0
        default:
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Widget Config
@main
struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Schedule Widget")
        .description("Shows your current and upcoming classes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview
#Preview(as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    SimpleEntry(date: .now, lines: [], dayCode: "G1")
}
