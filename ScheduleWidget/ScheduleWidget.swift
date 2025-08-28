import WidgetKit
import SwiftUI

// MARK: - Shared models (mirror the app's versions)
struct MiniRow: Codable {
    var title: String
    var timeRange: String
    var teacher: String?
    var room: String?
    var isCurrent: Bool
}

struct WidgetSnapshot: Codable {
    var updated: Date
    var current: MiniRow?
    var next: MiniRow?
}

// MARK: - Timeline Entry
struct ScheduleEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider
struct Provider: TimelineProvider {

    private let appGroupID = "group.com.yourcompany.schedule" // CHANGE ME

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), snapshot: .init(
            updated: Date(),
            current: MiniRow(title: "Math", timeRange: "9:00–9:45", teacher: "A. Smith", room: "210", isCurrent: true),
            next:    MiniRow(title: "English", timeRange: "9:50–10:35", teacher: "J. Doe", room: "105", isCurrent: false)
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(ScheduleEntry(date: Date(), snapshot: loadSnapshot() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let snap = loadSnapshot() ?? placeholder(in: context).snapshot
        // Choose a sensible refresh—e.g. 1 minute. Your app will also poke reloads.
        let entry = ScheduleEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard let data = defaults?.data(forKey: "widget_snapshot_v1") else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - View
struct ScheduleWidgetView: View {
    let snap: WidgetSnapshot

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowView(snap.current, label: "Now")
            Divider().opacity(0.2)
            rowView(snap.next, label: "Next")
            Spacer(minLength: 0)
        }
        .padding()
    }

    @ViewBuilder
    private func rowView(_ row: MiniRow?, label: String) -> some View {
        if let row {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label.uppercased())
                        .font(.caption2).bold()
                        .opacity(0.7)
                    if row.isCurrent {
                        Circle().frame(width: 6, height: 6)
                    }
                }
                Text(row.title)
                    .font(.headline)
                    .lineLimit(1)
                if !row.timeRange.isEmpty {
                    Text(row.timeRange).font(.caption).opacity(0.8)
                }
                HStack(spacing: 8) {
                    if let t = row.teacher, !t.isEmpty {
                        Text(t).font(.caption2).lineLimit(1)
                    }
                    if let r = row.room, !r.isEmpty {
                        Text("• \(r)").font(.caption2).lineLimit(1)
                    }
                }.opacity(0.8)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(.caption2).bold().opacity(0.7)
                Text("—").font(.headline).opacity(0.5)
            }
        }
    }
}

// MARK: - Widget
struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScheduleWidget", provider: Provider()) { entry in
            ScheduleWidgetView(snap: entry.snapshot)
        }
        .configurationDisplayName("Classes")
        .description("Shows the current and next class.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
