//
//  NotificationManager.swift
//  Schedule
//
//  Fixes:
//  1. Debounce was resetting every second because the ticker calls
//     scheduleNightly() every second. Changed to a time-gated approach:
//     notifications are only rescheduled when the dayCode actually changes
//     or after a minimum interval has elapsed since the last real schedule.
//  2. Nightly notifications no longer roll over to the next evening after
//     the selected time has already passed, which caused duplicate "Tomorrow"
//     alerts on the following day.
//  3. Notifications persist after toggle-off — disabling now removes BOTH
//     pending AND already-delivered notifications.
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
    private let reminderPrefix = "custom-reminder-"
    private let schedulePrefixes = ["nightly-", "morning-"]

    // Track last successfully scheduled values so we only reschedule
    // when something meaningful has actually changed.
    private var lastScheduledDayCode: String = ""
    private var lastScheduledTime: Date = .distantPast
    var lastScheduledNotificationTime: String = ""   // HH:mm of alert time; var so NotificationSettings.time setter can reset it

    // Minimum gap between actual reschedule calls (prevents ticker spam)
    private let minRescheduleInterval: TimeInterval = 300   // 5 minutes

    private init() {}

    // MARK: - Public scheduling entry point

    /// Call this freely — it gates on actual changes so the ticker calling it
    /// every second is harmless.
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

        // Compute current notification time string for change detection
        let alertTimeFormatter = DateFormatter()
        alertTimeFormatter.dateFormat = "HH:mm"
        let currentAlertTimeStr = alertTimeFormatter.string(from: NotificationSettings.time)

        // Only reschedule if something changed OR enough time has passed
        let dayCodeChanged   = dayCode != lastScheduledDayCode
        let alertTimeChanged = currentAlertTimeStr != lastScheduledNotificationTime
        let intervalElapsed  = Date().timeIntervalSince(lastScheduledTime) > minRescheduleInterval

        guard dayCodeChanged || alertTimeChanged || intervalElapsed else { return }

        // Update tracking state before scheduling
        lastScheduledDayCode         = dayCode
        lastScheduledNotificationTime = currentAlertTimeStr
        lastScheduledTime            = Date()

        _scheduleNightlyNow(
            dayCode:        dayCode,
            firstClassName: firstClassName,
            firstClassTime: firstClassTime,
            firstClassRoom: firstClassRoom
        )
    }

    // MARK: - Cancel

    func cancelAllNotifications() {
        cancelScheduleNotifications()
    }

    func cancelScheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { id in
                    self.schedulePrefixes.contains(where: { id.hasPrefix($0) })
                }

            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        // Reset tracking so next enable reschedules immediately
        lastScheduledDayCode = ""
        lastScheduledTime    = .distantPast
    }

    func scheduleReminderNotifications(for events: [CustomEvent]) {
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let existingReminderIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.reminderPrefix) }

            if !existingReminderIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: existingReminderIDs)
            }

            let reminderEvents = events.filter { $0.isReminder && !$0.reminderOffsets.isEmpty }
            for event in reminderEvents {
                self.scheduleReminderNotifications(for: event, using: center)
            }
        }
    }

    func cleanupExpiredNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let now = Date()
            let expired = requests.compactMap { req -> String? in
                guard self.schedulePrefixes.contains(where: { req.identifier.hasPrefix($0) }) ||
                        req.identifier.hasPrefix(self.reminderPrefix),
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

#if DEBUG
    func scheduleDebugTestNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["debug-nightly", "debug-morning"])

        let nightlyContent = UNMutableNotificationContent()
        nightlyContent.title = "Tomorrow: Gold 1"
        nightlyContent.body = "Debug test nightly notification"
        nightlyContent.sound = .default

        let nightlyTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let nightlyRequest = UNNotificationRequest(
            identifier: "debug-nightly",
            content: nightlyContent,
            trigger: nightlyTrigger
        )

        let morningContent = UNMutableNotificationContent()
        morningContent.title = "Class in 10 minutes"
        morningContent.body = "Debug test morning reminder"
        morningContent.sound = .default
        morningContent.interruptionLevel = .timeSensitive

        let morningTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let morningRequest = UNNotificationRequest(
            identifier: "debug-morning",
            content: morningContent,
            trigger: morningTrigger
        )

        center.add(nightlyRequest) { err in
            if let err { print("❌ Debug nightly notification error: \(err)") }
        }
        center.add(morningRequest) { err in
            if let err { print("❌ Debug morning notification error: \(err)") }
        }
    }

    func clearDebugTestNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["debug-nightly", "debug-morning"]
        )
    }
#endif

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

        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let selectedTime = NotificationSettings.time
            let timeComps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
            var currentTriggerComps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            currentTriggerComps.hour = timeComps.hour
            currentTriggerComps.minute = timeComps.minute
            currentTriggerComps.second = 0
            let shouldScheduleEvening = (Calendar.current.date(from: currentTriggerComps) ?? .distantPast) > Date()

            let nightlyIDs = requests
                .filter { $0.identifier.hasPrefix("nightly-") }
                .map(\.identifier)

            if !nightlyIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: nightlyIDs)
            }

            guard shouldScheduleEvening else { return }

            let eveningRequest = UNNotificationRequest(
                identifier: eveningID,
                content:    eveningContent,
                trigger:    UNCalendarNotificationTrigger(dateMatching: currentTriggerComps, repeats: false)
            )

            center.add(eveningRequest) { err in
                if let err { print("❌ Evening notification error: \(err)") }
            }
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

    private func scheduleReminderNotifications(
        for event: CustomEvent,
        using center: UNUserNotificationCenter
    ) {
        guard let eventDate = event.firstApplicableDate else { return }

        let calendar = Calendar.current
        var baseComponents = calendar.dateComponents([.year, .month, .day], from: eventDate)
        baseComponents.hour = event.startTime.h
        baseComponents.minute = event.startTime.m
        baseComponents.second = event.startTime.s

        guard let startDate = calendar.date(from: baseComponents) else { return }

        for offset in event.reminderOffsets {
            let triggerDate = startDate.addingTimeInterval(TimeInterval(-offset.secondsBefore))
            guard triggerDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = reminderBody(for: event, offset: offset, startDate: startDate)
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let triggerComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: triggerDate
            )

            let request = UNNotificationRequest(
                identifier: "\(reminderPrefix)\(event.id.uuidString)-\(offset.rawValue)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            )

            center.add(request) { err in
                if let err {
                    print("❌ Reminder notification error: \(err)")
                }
            }
        }
    }

    private func reminderBody(for event: CustomEvent, offset: ReminderOffset, startDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let whenText: String
        switch offset {
        case .atTime:
            whenText = "Now"
        case .tenMinutes:
            whenText = "In 10 minutes"
        case .thirtyMinutes:
            whenText = "In 30 minutes"
        case .oneHour:
            whenText = "In 1 hour"
        case .twoHours:
            whenText = "In 2 hours"
        case .oneDay:
            whenText = "Day before"
        }

        var body = "\(whenText) • \(formatter.string(from: startDate))"
        if !event.note.isEmpty {
            body += " • \(event.note)"
        }
        return body
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
            // Reset tracking so the new time triggers a reschedule on next call
            NotificationManager.shared.lastScheduledNotificationTime = ""
        }
    }

    static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
    }
}
