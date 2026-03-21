//
//  LiveActivityManager.swift
//  Schedule
//
//  The widget now redraws itself at every class boundary via TimelineView,
//  so this manager only needs to START the activity (with the full schedule
//  baked in) and END it when school is over. No per-class updates required.
//

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<ScheduleWidgetAttributes>?

    // MARK: - Public API

    func update(scheduleLines: [ScheduleLine], dayCode: String, dayName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Clean up any externally dismissed/ended reference
        if let existing = activity {
            switch existing.activityState {
            case .dismissed, .ended: activity = nil
            case .active, .stale:   break
            @unknown default:       activity = nil
            }
        }

        let nowDate = Date()
        let nowSec  = Time.now().seconds

        let realClasses = scheduleLines
            .filter { $0.startSec != nil && $0.endSec != nil && $0.className != "Passing Period" }
            .sorted { ($0.startSec ?? 0) < ($1.startSec ?? 0) }

        // Nothing left today → end
        guard realClasses.contains(where: { ($0.endSec ?? 0) > nowSec }) else {
            endActivity()
            return
        }

        let scheduledClasses = realClasses.map {
            ScheduleWidgetAttributes.ScheduledClass(
                className: $0.className,
                room:      $0.room,
                teacher:   $0.teacher,
                timeRange: $0.timeRange,
                startSec:  $0.startSec ?? 0,
                endSec:    $0.endSec   ?? 0
            )
        }

        let lastEndSec   = realClasses.compactMap(\.endSec).max() ?? (nowSec + 3600)
        let schoolEndDate = wallDate(lastEndSec, reference: nowDate)

        let state   = ScheduleWidgetAttributes.ContentState(updatedAt: nowDate)
        // staleDate = school end so the system dismisses the activity automatically
        let content = ActivityContent(state: state, staleDate: schoolEndDate)

        if let existing = activity {
            // Already running — just heartbeat so the system knows we're alive.
            // The TimelineView inside the widget handles all visual transitions.
            Task { await existing.update(content) }
        } else {
            let attributes = ScheduleWidgetAttributes(
                dayCode:          dayCode,
                dayName:          dayName,
                scheduledClasses: scheduledClasses,
                schoolEndDate:    schoolEndDate
            )
            do {
                activity = try Activity<ScheduleWidgetAttributes>.request(
                    attributes: attributes,
                    content:    content,
                    pushType:   nil
                )
                print("✅ LiveActivity started")
            } catch {
                print("❌ LiveActivity failed — \(error.localizedDescription)")
            }
        }
    }

    func endActivity() {
        guard let existing = activity else { return }
        activity = nil
        Task { await existing.end(using: nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Private

    private func wallDate(_ sec: Int, reference: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: reference)
        comps.hour   = sec / 3600
        comps.minute = (sec % 3600) / 60
        comps.second = sec % 60
        return Calendar.current.date(from: comps) ?? reference.addingTimeInterval(TimeInterval(sec))
    }
}
