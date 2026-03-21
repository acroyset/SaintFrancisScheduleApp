//
//  ScheduleWidgetLiveActivity.swift
//  ScheduleWidget
//
//  TimelineView fires a redraw at each class boundary so the widget
//  redraws itself without any app involvement.
//
//  Key rules:
//  • currentDisplay(at: Date()) — always use real Date(), never timeline.date
//  • timerInterval: Date.now...end — always use Date.now as the start
//  • timeline.date is only used to TRIGGER the redraw, not for any logic
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Attributes

struct ScheduleWidgetAttributes: ActivityAttributes {
    var dayCode: String
    var dayName: String
    var scheduledClasses: [ScheduledClass]
    var schoolEndDate: Date

    struct ScheduledClass: Codable, Hashable {
        var className: String
        var room: String
        var teacher: String
        var timeRange: String
        var startSec: Int
        var endSec: Int
    }

    public struct ContentState: Codable, Hashable {
        var updatedAt: Date
    }
}

// MARK: - Attribute helpers

extension ScheduleWidgetAttributes {
    /// Always call with Date() — not timeline.date
    func currentDisplay() -> (cls: ScheduledClass, isCurrent: Bool, next: ScheduledClass?)? {
        let nowSec  = secsSinceMidnight(Date())
        let current = scheduledClasses.first { $0.startSec <= nowSec && nowSec < $0.endSec }
        let next    = scheduledClasses.first { $0.startSec > nowSec }
        guard let display = current ?? next else { return nil }
        let after = scheduledClasses.first { $0.startSec > display.endSec }
        return (display, current != nil, after)
    }

    /// Dates fed to TimelineView — only used to trigger redraws, not for logic
    func classBoundaryDates() -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        var dates: [Date] = []
        for cls in scheduledClasses {
            dates.append(today.addingTimeInterval(TimeInterval(cls.startSec)))
            dates.append(today.addingTimeInterval(TimeInterval(cls.endSec)))
        }
        return dates.filter { $0 > Date() }.sorted()
    }

    func wallDate(secSinceMidnight: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return today.addingTimeInterval(TimeInterval(secSinceMidnight))
    }

    func progress(for cls: ScheduledClass) -> Double {
        let nowSec   = secsSinceMidnight(Date())
        let duration = cls.endSec - cls.startSec
        guard duration > 0 else { return 0 }
        return max(0, min(1, Double(nowSec - cls.startSec) / Double(duration)))
    }
}

private func secsSinceMidnight(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
}

// MARK: - SplitProgressBar

private struct SplitProgressBar: View {
    let progress: Double
    let label: String

    private let barFill     = Color.blue
    private let barTrack    = Color.white.opacity(0.18)
    private let textOnFill  = Color.black
    private let textOnTrack = Color.white

    var body: some View {
        GeometryReader { geo in
            let fillW = geo.size.width * progress
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).fill(barTrack)
                RoundedRectangle(cornerRadius: 7).fill(barFill)
                    .frame(width: max(0, fillW))
                labelText(color: textOnTrack).frame(maxWidth: .infinity)
                labelText(color: textOnFill).frame(maxWidth: .infinity)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, fillW))
                    }
            }
        }
        .frame(height: 26)
    }

    private func labelText(color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(height: 26)
    }
}

// MARK: - Widget

struct ScheduleWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleWidgetAttributes.self) { context in
            // timeline.date triggers the redraw — all logic inside uses Date()
            TimelineView(.explicit(context.attributes.classBoundaryDates())) { _ in
                LiveActivityBannerView(attributes: context.attributes)
            }
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.explicit(context.attributes.classBoundaryDates())) { _ in
                        ExpandedLeadingView(attributes: context.attributes)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.explicit(context.attributes.classBoundaryDates())) { _ in
                        ExpandedTrailingView(attributes: context.attributes)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.explicit(context.attributes.classBoundaryDates())) { _ in
                        ExpandedBottomView(attributes: context.attributes)
                    }
                }
            } compactLeading: {
                Image(systemName: "clock.fill").foregroundStyle(.blue).font(.caption)
            } compactTrailing: {
                TimelineView(.explicit(context.attributes.classBoundaryDates())) { _ in
                    CompactTrailingView(attributes: context.attributes)
                }
            } minimal: {
                Image(systemName: "clock.fill").foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "scheduleapp://home"))
            .keylineTint(.blue)
        }
    }
}

// MARK: - Sub-views — all call currentDisplay() with no arguments (uses Date() internally)

private struct ExpandedLeadingView: View {
    let attributes: ScheduleWidgetAttributes
    var body: some View {
        let info = attributes.currentDisplay()
        VStack(alignment: .leading, spacing: 2) {
            Text(info?.isCurrent == true ? "Now" : "Up Next")
                .font(.caption2).foregroundStyle(.secondary)
            Text(info?.cls.className ?? "—")
                .font(.headline).lineLimit(1)
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailingView: View {
    let attributes: ScheduleWidgetAttributes
    var body: some View {
        let info = attributes.currentDisplay()
        VStack(alignment: .trailing, spacing: 2) {
            if info?.isCurrent == true, let cls = info?.cls {
                // Timer always starts from Date.now — never from timeline.date
                let end = max(attributes.wallDate(secSinceMidnight: cls.endSec),
                              Date.now.addingTimeInterval(1))
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.blue)
            } else {
                Text(info?.cls.timeRange ?? "—")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let room = info?.cls.room, !room.isEmpty {
                Text(room).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 4)
    }
}

private struct ExpandedBottomView: View {
    let attributes: ScheduleWidgetAttributes
    var body: some View {
        let info = attributes.currentDisplay()
        if let next = info?.next, info?.isCurrent == true {
            HStack {
                Text("Next:").font(.caption2).foregroundStyle(.secondary)
                Text(next.className).font(.caption2)
            }
        }
    }
}

private struct CompactTrailingView: View {
    let attributes: ScheduleWidgetAttributes
    var body: some View {
        let info = attributes.currentDisplay()
        if info?.isCurrent == true, let cls = info?.cls {
            let end = max(attributes.wallDate(secSinceMidnight: cls.endSec),
                          Date.now.addingTimeInterval(1))
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.blue)
                .frame(width: 44)
        } else {
            Text(info?.cls.timeRange.components(separatedBy: " to").first ?? "")
                .font(.caption2).foregroundStyle(.blue)
        }
    }
}

private struct LiveActivityBannerView: View {
    let attributes: ScheduleWidgetAttributes

    var body: some View {
        let info      = attributes.currentDisplay()
        let cls       = info?.cls
        let isCurrent = info?.isCurrent ?? false
        let progress  = cls.map { attributes.progress(for: $0) } ?? 0
        let endDate   = cls.map {
            max(attributes.wallDate(secSinceMidnight: $0.endSec),
                Date.now.addingTimeInterval(1))
        } ?? Date.now.addingTimeInterval(1)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isCurrent ? "IN CLASS" : "UP NEXT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
                Spacer()
                Text(attributes.dayName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.75))
            }

            SplitProgressBar(
                progress: isCurrent ? progress : 0,
                label: cls?.className ?? "—"
            )

            HStack(spacing: 12) {
                Label(cls?.timeRange ?? "—", systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
                if let room = cls?.room, !room.isEmpty {
                    Label(room, systemImage: "mappin")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    // Always Date.now as start — never timeline.date
                    Text(timerInterval: Date.now...endDate, countsDown: true)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let next = info?.next, isCurrent {
                Text("Next: \(next.className)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

extension ScheduleWidgetAttributes {
    fileprivate static var preview: ScheduleWidgetAttributes {
        ScheduleWidgetAttributes(
            dayCode: "G1",
            dayName: "Gold 1 Day",
            scheduledClasses: [
                ScheduledClass(className: "Advisory",   room: "",    teacher: "",           timeRange: "7:55 to 8:55",   startSec: 7*3600+55*60,  endSec: 8*3600+55*60),
                ScheduledClass(className: "AP Biology", room: "213", teacher: "Mrs. Smith", timeRange: "9:00 to 10:20",  startSec: 9*3600,         endSec: 10*3600+20*60),
                ScheduledClass(className: "Brunch",     room: "",    teacher: "",           timeRange: "10:25 to 10:55", startSec: 10*3600+25*60,  endSec: 10*3600+55*60),
            ],
            schoolEndDate: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date())!
        )
    }
}

extension ScheduleWidgetAttributes.ContentState {
    fileprivate static var sample: ScheduleWidgetAttributes.ContentState {
        .init(updatedAt: Date())
    }
}

#Preview("Notification", as: .content, using: ScheduleWidgetAttributes.preview) {
    ScheduleWidgetLiveActivity()
} contentStates: {
    ScheduleWidgetAttributes.ContentState.sample
}
