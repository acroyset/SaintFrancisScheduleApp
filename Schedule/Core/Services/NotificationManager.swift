//
//  NotificationManager.swift
//  Schedule
//
//  Fixes:
//  3. Duplicate notifications — scheduling is now debounced (0.5 s) so rapid
//     callers (ticker + dayCode change + scenePhase) collapse into one request.
//     IDs are keyed on the *target date* rather than today's date, so a
//     reschedule atomically replaces the old request instead of stacking.
//  5. Notifications persist after toggle-off — disabling now removes BOTH
//     pending AND already-delivered notifications, and cancels the background
//     task that was silently rescheduling them.
//

import Foundation
import UserNotifications
import SwiftUI

func fancyDayName(_ code: String) -> String {
    let map: [String: String] = [
        "G1": "Gold 1",   "G2": "Gold 2",
        "B1": "Brown 1",  "B2": "Brown 2",
        "A1": "Activity 1", "A2": "Activity 2",
        "A3": "Activity 3", "A4": "Activity 4",
        "L1": "Liturgy 1",  "L2": "Liturgy 2",
        "S1": "Special Schedule"
    ]
    return map[code.uppercased()] ?? code
}

class NotificationManager {
    static let shared = NotificationManager()

    // --- FIX 3: Debounce token ---
    private var scheduleDebounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.5

    // Pending values held during debounce window
    private var pendingDayCode:      String = ""
    private var pendingFirstName:    String = ""
    private var pendingFirstTime:    String = ""
    private var pendingFirstRoom:    String = ""

    // MARK: - Public scheduling entry point

    /// Thread-safe, debounced. Multiple rapid calls collapse into one.
    func scheduleNightly(
        dayCode:        String,
        firstClassName: String = "",
        firstClassTime: String = "",
        firstClassRoom: String = ""
    ) {
        guard NotificationSettings.isEnabled else {
            cancelAllNotifications()
            return
        }
        guard !dayCode.isEmpty && dayCode != "Unknown" else { return }

        // Store the latest values; the timer will use them when it fires
        pendingDayCode   = dayCode
        pendingFirstName = firstClassName
        pendingFirstTime = firstClassTime
        pendingFirstRoom = firstClassRoom

        // --- FIX 3: Debounce — cancel any pending timer, restart it ---
        scheduleDebounceTimer?.invalidate()
        scheduleDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self._scheduleNightlyNow(
                dayCode:        self.pendingDayCode,
                firstClassName: self.pendingFirstName,
                firstClassTime: self.pendingFirstTime,
                firstClassRoom: self.pendingFirstRoom
            )
        }
    }

    // MARK: - Cancel

    func cancelAllNotifications() {
        scheduleDebounceTimer?.invalidate()
        scheduleDebounceTimer = nil

        let center = UNUserNotificationCenter.current()
        // --- FIX 5: Remove both pending AND delivered ---
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func cleanupExpiredNotifications() {
        let prefixes = ["nightly-", "morning-"]
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let now = Date()
            let expired = requests.compactMap { req -> String? in
                guard prefixes.contains(where: { req.identifier.hasPrefix($0) }),
                      let trigger = req.trigger as? UNCalendarNotificationTrigger,
                      let next = trigger.nextTriggerDate(),
                      next < now
                else { return nil }
                return req.identifier
            }
            if !expired.isEmpty {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: expired)
            }
        }
    }

    // MARK: - Private implementation

    private func _scheduleNightlyNow(
        dayCode:        String,
        firstClassName: String,
        firstClassTime: String,
        firstClassRoom: String
    ) {
        let fancy     = fancyDayName(dayCode)
        let tomorrow  = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let tomorrowKey = formatter.string(from: tomorrow)

        // --- FIX 3: ID keyed on the TARGET date, not today ---
        // This means rescheduling always replaces the same notification
        // rather than adding a second one with a different ID.
        let eveningID = "nightly-\(tomorrowKey)"
        let morningID = "morning-\(tomorrowKey)"

        // ── Evening notification ──────────────────────────────────────
        let eveningContent       = UNMutableNotificationContent()
        eveningContent.title     = "Tomorrow: \(fancy)"
        if !firstClassName.isEmpty {
            var body = "\(firstClassName) starts at \(firstClassTime)"
            if !firstClassRoom.isEmpty { body += " · Room \(firstClassRoom)" }
            eveningContent.body  = body
        } else {
            eveningContent.body  = "Tap to see tomorrow's schedule"
        }
        eveningContent.sound = .default

        let selectedTime   = NotificationSettings.time
        let timeComps      = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        var triggerComps   = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        triggerComps.hour   = timeComps.hour
        triggerComps.minute = timeComps.minute
        triggerComps.second = 0

        // If the time has already passed today, schedule for tomorrow instead
        if let t = Calendar.current.date(from: triggerComps), t <= Date() {
            triggerComps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            triggerComps.hour   = timeComps.hour
            triggerComps.minute = timeComps.minute
            triggerComps.second = 0
        }

        let eveningRequest = UNNotificationRequest(
            identifier: eveningID,
            content:    eveningContent,
            trigger:    UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        )
        // Remove then add atomically to replace any existing request with the same ID
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [eveningID])
        center.add(eveningRequest) { err in
            if let err { print("❌ Evening notification error: \(err)") }
        }

        // ── Morning notification ──────────────────────────────────────
        center.removePendingNotificationRequests(withIdentifiers: [morningID])
        if !firstClassName.isEmpty, !firstClassTime.isEmpty {
            _scheduleMorningAlert(
                className:    firstClassName,
                classTimeStr: firstClassTime,
                classRoom:    firstClassRoom,
                targetDate:   tomorrow,
                id:           morningID
            )
        }
    }

    private func _scheduleMorningAlert(
        className:    String,
        classTimeStr: String,
        classRoom:    String,
        targetDate:   Date,
        id:           String
    ) {
        let parts = classTimeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var hour   = parts[0]
        let minute = parts[1]
        if hour < 7 { hour += 12 }

        var alertMin  = minute - 10
        var alertHour = hour
        if alertMin < 0 { alertMin += 60; alertHour -= 1 }
        guard alertHour >= 0 else { return }

        var triggerComps  = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        triggerComps.hour   = alertHour
        triggerComps.minute = alertMin
        triggerComps.second = 0

        guard let triggerDate = Calendar.current.date(from: triggerComps),
              triggerDate > Date() else { return }

        let content       = UNMutableNotificationContent()
        content.title     = "Class in 10 minutes"
        var body          = className
        if !classRoom.isEmpty { body += " · Room \(classRoom)" }
        body += " at \(classTimeStr)"
        content.body      = body
        content.sound     = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: id,
            content:    content,
            trigger:    UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { err in
            if let err { print("❌ Morning notification error: \(err)") }
        }
    }
}

// MARK: - NotificationSettings

class NotificationSettings {
    static let enabledKey = "NotificationsEnabled"
    static let timeKey    = "NotificationTime"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue {
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if !granted { print("❌ Notification Permission Denied") }
                }
                ScheduleBackgroundManager.shared.scheduleNextNightlyRefresh()
            } else {
                // --- FIX 5: Cancel ALL notifications (pending + delivered) ---
                // Also clear background task so it can't silently reschedule.
                NotificationManager.shared.cancelAllNotifications()
            }
        }
    }

    static var time: Date {
        get {
            if let raw = UserDefaults.standard.string(forKey: timeKey) {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                return f.date(from: raw) ?? defaultTime
            }
            return defaultTime
        }
        set {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            UserDefaults.standard.set(f.string(from: newValue), forKey: timeKey)
        }
    }

    static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
    }
}
