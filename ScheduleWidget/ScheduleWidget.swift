// ScheduleWidget.swift
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    let message: String
}

// MARK: - Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), message: "Placeholder")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), message: "Snapshot Example")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let entries = [
            SimpleEntry(date: Date(), message: "Hello Widget!"),
            SimpleEntry(date: Date().addingTimeInterval(60 * 30), message: "Updated message")
        ]
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// MARK: - Widget View
struct ScheduleWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            Color.blue
            VStack {
                Text(entry.message)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
        }
    }
}

// MARK: - Widget Configuration
@main
struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Schedule Widget")
        .description("This is an example widget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview
struct ScheduleWidget_Previews: PreviewProvider {
    static var previews: some View {
        ScheduleWidgetEntryView(entry: SimpleEntry(date: Date(), message: "Preview"))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
