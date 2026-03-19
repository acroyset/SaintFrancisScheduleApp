//
//  LiveActivityManager.swift
//  Schedule
//

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<ScheduleWidgetAttributes>?

    /// Track the last class we showed so we detect transitions
    private var lastClassName: String = ""

    // MARK: - Public API

    func update(scheduleLines: [ScheduleLine], dayCode: String, dayName: String) {

        // ── 1. Permission check ───────────────────────────────────────────
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // ── 2. Clear stale reference if dismissed/ended externally ────────
        if let existing = activity {
            switch existing.activityState {
            case .dismissed, .ended:
                activity = nil
                lastClassName = ""
            case .active, .stale:
                break
            @unknown default:
                activity = nil
                lastClassName = ""
            }
        }

        // ── 3. Find current or next class ─────────────────────────────────
        // Include passing periods this time so we don't skip over them
        // when searching, but only show real classes in the activity.
        let now = Time.now().seconds
        let nowDate = Date()

        // All lines with valid times, sorted
        let timed = scheduleLines.filter { $0.startSec != nil && $0.endSec != nil }

        // Current class = a real class (not passing period) happening right now
        let currentClass = timed.first(where: {
            guard let s = $0.startSec, let e = $0.endSec else { return false }
            return $0.className != "Passing Period" && s <= now && now < e
        })

        // Next class = next real class that hasn't started yet
        let nextRealClass = timed.first(where: {
            guard let s = $0.startSec else { return false }
            return $0.className != "Passing Period" && s > now
        })

        // What to display — current if in class, otherwise next upcoming
        guard let current = currentClass ?? nextRealClass else {
            endActivity()
            return
        }

        let isCurrentClass = currentClass != nil
        let endSec = current.endSec ?? (now + 3600)

        // ── 4. Build end Date ─────────────────────────────────────────────
        var components = Calendar.current.dateComponents([.year, .month, .day], from: nowDate)
        components.hour   = endSec / 3600
        components.minute = (endSec % 3600) / 60
        components.second = endSec % 60
        let endDate = Calendar.current.date(from: components) ?? nowDate.addingTimeInterval(3600)

        // Allow a 5-second buffer at the boundary so the transition second
        // doesn't accidentally call endActivity() before the next class loads
        guard endDate > nowDate.addingTimeInterval(-5) else {
            endActivity()
            return
        }

        // Clamp endDate so it's never in the past for the timer display
        let displayEndDate = max(endDate, nowDate.addingTimeInterval(1))

        let nextAfterCurrent = timed.first(where: {
            guard let s = $0.startSec else { return false }
            return $0.className != "Passing Period" && s > (current.endSec ?? 0)
        })

        // ── 5. Detect class change → end old, start fresh ─────────────────
        if activity != nil && current.className != lastClassName && !lastClassName.isEmpty {
            let old = activity
            activity = nil
            lastClassName = ""
            Task {
                await old?.end(using: nil, dismissalPolicy: .immediate)
            }
        }

        let state = ScheduleWidgetAttributes.ContentState(
            className: current.className,
            room: current.room,
            teacher: current.teacher,
            timeRange: current.timeRange,
            endTimestamp: displayEndDate,
            isCurrentClass: isCurrentClass,
            nextClassName: nextAfterCurrent?.className ?? ""
        )

        // ── 6. Update existing or start fresh ────────────────────────────
        if let existing = activity {
            Task {
                await existing.update(using: state)
            }
        } else {
            let attributes = ScheduleWidgetAttributes(dayCode: dayCode, dayName: dayName)
            let content = ActivityContent(state: state, staleDate: displayEndDate)
            do {
                activity = try Activity<ScheduleWidgetAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                lastClassName = current.className
                print("✅ LiveActivity: started — \(current.className)")
            } catch {
                print("❌ LiveActivity: failed to start — \(error.localizedDescription)")
            }
        }
    }

    func endActivity() {
        guard let existing = activity else { return }
        activity = nil
        lastClassName = ""
        Task {
            await existing.end(using: nil, dismissalPolicy: .immediate)
        }
    }
}
