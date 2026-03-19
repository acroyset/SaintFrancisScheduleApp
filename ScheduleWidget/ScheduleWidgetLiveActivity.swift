//
//  ScheduleWidgetLiveActivity.swift
//  ScheduleWidget
//
//  Created by Andreas Royset on 3/19/26.
//
//
//  Live Activity that shows the current / next class with a countdown.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Attributes (shared with main app via module boundary — keep Codable/simple)

struct ScheduleWidgetAttributes: ActivityAttributes {

    // Fixed info set when the activity is started
    var dayCode: String
    var dayName: String

    // Dynamic state updated as time passes
    public struct ContentState: Codable, Hashable {
        var className: String
        var room: String
        var teacher: String
        var timeRange: String
        var endTimestamp: Date      // used for timer display
        var isCurrentClass: Bool    // false → "upcoming"
        var nextClassName: String   // peek at what's next
    }
}

// MARK: - Widget implementation

struct ScheduleWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleWidgetAttributes.self) { context in
            // ── Lock-screen / banner view ──────────────────────────────────
            LiveActivityBannerView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isCurrentClass ? "Now" : "Up Next")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.className)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.isCurrentClass {
                            Text(timerInterval: Date.now...context.state.endTimestamp,
                                 countsDown: true)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                        } else {
                            Text(context.state.timeRange)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !context.state.room.isEmpty {
                            Text(context.state.room)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.nextClassName.isEmpty &&
                        context.state.isCurrentClass {
                        HStack {
                            Text("Next:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(context.state.nextClassName)
                                .font(.caption2)
                        }
                    }
                }

            } compactLeading: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            } compactTrailing: {
                if context.state.isCurrentClass {
                    Text(timerInterval: Date.now...context.state.endTimestamp,
                         countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 40)
                } else {
                    Text(context.state.timeRange.components(separatedBy: " to").first ?? "")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            } minimal: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "scheduleapp://home"))
            .keylineTint(.blue)
        }
    }
}

// MARK: - Lock-screen banner

private struct LiveActivityBannerView: View {
    let context: ActivityViewContext<ScheduleWidgetAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Left accent column
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue)
                    .frame(width: 4)
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                // Label row
                HStack {
                    Text(context.state.isCurrentClass ? "IN CLASS" : "UP NEXT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)

                    Spacer()

                    Text(context.attributes.dayName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Class name
                Text(context.state.className)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Details row
                HStack(spacing: 12) {
                    Label(context.state.timeRange, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !context.state.room.isEmpty {
                        Label(context.state.room, systemImage: "mappin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Countdown
                    if context.state.isCurrentClass {
                        Text(timerInterval: Date.now...context.state.endTimestamp,
                             countsDown: true)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Next class peek
                if !context.state.nextClassName.isEmpty && context.state.isCurrentClass {
                    Text("Next: \(context.state.nextClassName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

extension ScheduleWidgetAttributes {
    fileprivate static var preview: ScheduleWidgetAttributes {
        ScheduleWidgetAttributes(dayCode: "G1", dayName: "Gold 1 Day")
    }
}

extension ScheduleWidgetAttributes.ContentState {
    fileprivate static var current: ScheduleWidgetAttributes.ContentState {
        .init(
            className: "AP Biology",
            room: "213",
            teacher: "Mrs. Smith",
            timeRange: "9:00 to 10:20",
            endTimestamp: Date().addingTimeInterval(45 * 60),
            isCurrentClass: true,
            nextClassName: "Brunch"
        )
    }
    fileprivate static var upcoming: ScheduleWidgetAttributes.ContentState {
        .init(
            className: "AP Biology",
            room: "213",
            teacher: "Mrs. Smith",
            timeRange: "9:00 to 10:20",
            endTimestamp: Date().addingTimeInterval(15 * 60),
            isCurrentClass: false,
            nextClassName: ""
        )
    }
}

#Preview("Notification", as: .content, using: ScheduleWidgetAttributes.preview) {
    ScheduleWidgetLiveActivity()
} contentStates: {
    ScheduleWidgetAttributes.ContentState.current
    ScheduleWidgetAttributes.ContentState.upcoming
}
