//
//  LiveActivityManager.swift
//  Schedule
//
//  Fixes:
//  1. Duplicate activities — guard checks ALL non-active states before requesting
//  2. Progress bar stale — classBoundaryDates() now includes per-minute ticks
//     during the current class so TimelineView redraws without app involvement
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

        // --- FIX 1: Properly resolve stale activity references ---
        // Any state other than .active means we should nil the reference
        // so we request a fresh one rather than trying to update a dead one.
        if let existing = activity {
            switch existing.activityState {
            case .active:
                break // keep it
            case .stale, .ended, .dismissed:
                activity = nil
            @unknown default:
                activity = nil
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

        if let existing = activity {
            // Already active — heartbeat so the system knows we're alive.
            // The TimelineView inside handles all visual transitions.
            Task { await existing.update(content) }
        } else {
            // --- FIX 1 (continued): Only call .request() when activity is nil ---
            // Before requesting, terminate any orphaned activities from a previous
            // session that we lost the reference to.
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

    /// Ends any activities from a previous session that we no longer hold a
    /// reference to. This prevents the duplicate-on-launch bug where the app
    /// crashed or was killed while an activity was running.
    private func terminateOrphanedActivities(dayCode: String) {
        let orphans = Activity<ScheduleWidgetAttributes>.activities.filter { a in
            // If we already have a reference to this one, skip it
            guard a.id != activity?.id else { return false }
            // End anything that isn't already done
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
