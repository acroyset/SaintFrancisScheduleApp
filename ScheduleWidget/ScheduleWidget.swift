// Enhanced ScheduleWidget.swift with Auto-updating Schedule
import WidgetKit
import SwiftUI



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
