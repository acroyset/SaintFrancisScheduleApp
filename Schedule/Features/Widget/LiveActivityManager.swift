//
//  LiveActivityManager.swift
//  Schedule
//
//  Fixes:
//  1. Duplicate activities — guard checks ALL non-active states before requesting
//  2. Class transitions — when scheduledClasses change we end + restart so
//     the new immutable attributes take effect (attributes cannot be mutated
//     after an activity is created; only ContentState can be updated).
//  3. Progress bar — the TimelineView inside the Live Activity fires per
//     classBoundaryDates(); we now also call update() every minute from the
//     app so the stale date is pushed forward.
//

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    // Snapshot of scheduledClasses used when the activity was last started,
    // so we can detect when the class list has actually changed.
    private var activity: Activity<ScheduleWidgetAttributes>?
    private var lastScheduledClasses: [ScheduleWidgetAttributes.ScheduledClass] = []

    // MARK: - Public API

    func update(scheduleLines: [ScheduleLine], dayCode: String, dayName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Resolve stale references
        if let existing = activity {
            switch existing.activityState {
            case .active:
                break
            case .stale, .ended, .dismissed:
                activity = nil
                lastScheduledClasses = []
            @unknown default:
                activity = nil
                lastScheduledClasses = []
            }
        }

        let nowDate = Date()
        let nowSec  = Time.now().seconds

        let realClasses = scheduleLines
            .filter { $0.startSec != nil && $0.endSec != nil && $0.className != "Passing Period" }
            .sorted { ($0.startSec ?? 0) < ($1.startSec ?? 0) }

        // Nothing left today → end any running activity
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

        let lastEndSec    = realClasses.compactMap(\.endSec).max() ?? (nowSec + 3600)
        let schoolEndDate = wallDate(lastEndSec, reference: nowDate)

        let state   = ScheduleWidgetAttributes.ContentState(updatedAt: nowDate)
        let content = ActivityContent(state: state, staleDate: schoolEndDate)

        // Check whether the class list has changed since we last started
        // the activity. Because attributes are immutable we must end + restart.
        let classesChanged = scheduledClasses != lastScheduledClasses

        if let existing = activity, !classesChanged {
            // Same schedule — just heartbeat so staleDate advances
            Task { await existing.update(content) }
        } else {
            // New schedule or no activity yet — end the old one and start fresh
            if activity != nil {
                endActivity()
            }

            terminateOrphanedActivities(dayCode: dayCode)

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
                lastScheduledClasses = scheduledClasses
                print("✅ LiveActivity started/refreshed")
            } catch {
                print("❌ LiveActivity failed — \(error.localizedDescription)")
            }
        }
    }

    func endActivity() {
        guard let existing = activity else { return }
        activity = nil
        lastScheduledClasses = []
        Task { await existing.end(using: nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Private

    private func terminateOrphanedActivities(dayCode: String) {
        let orphans = Activity<ScheduleWidgetAttributes>.activities.filter { a in
            guard a.id != activity?.id else { return false }
            switch a.activityState {
            case .active, .stale: return true
            default: return false
            }
        }
        for orphan in orphans {
            Task { await orphan.end(using: nil, dismissalPolicy: .immediate) }
            print("🧹 Terminated orphaned LiveActivity: \(orphan.id)")
        }
    }

    private func wallDate(_ sec: Int, reference: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: reference)
        comps.hour   = sec / 3600
        comps.minute = (sec % 3600) / 60
        comps.second = sec % 60
        return Calendar.current.date(from: comps) ?? reference.addingTimeInterval(TimeInterval(sec))
    }
}
