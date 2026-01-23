//  Enhanced ScheduleWidget.swift with Auto-updating Schedule
import WidgetKit
import SwiftUI

struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Schedule Widget")
        .description("Shows your current and upcoming classes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    SimpleEntry(date: .now, lines: [], dayCode: "G1")
}

#Preview(as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    SimpleEntry(date: .now, lines: [], dayCode: "G1")
}
