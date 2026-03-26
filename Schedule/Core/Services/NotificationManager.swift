//
//  NotificationManager.swift
//  Schedule
//
//  Updated: Notifications now include class name, room, and time.
//  Added a morning "class starts in 10 min" alert.
//

import Foundation
import UserNotifications
import SwiftUI

func fancyDayName(_ code: String) -> String {
    let map: [String: String] = [
        "G1": "Gold 1",
        "G2": "Gold 2",
        "B1": "Brown 1",
        "B2": "Brown 2",
        "A1": "Activity 1",
        "A2": "Activity 2",
        "A3": "Activity 3",
        "A4": "Activity 4",
        "L1": "Liturgy 1",
        "L2": "Liturgy 2",
        "S1": "Special Schedule"
    ]
    return map[code.uppercased()] ?? code
}

class NotificationManager {
    static let shared = NotificationManager()
    private let nightlyIDPrefix  = "nightly"
    private let morningIDPrefix  = "morning"

    // MARK: - Schedule nightly + morning alerts

    /// Call this whenever schedule data changes.
    /// - Parameters:
    ///   - dayCode: Tomorrow's day code (e.g. "G2")
    ///   - firstClassName: Name of first period class tomorrow (optional)
    ///   - firstClassTime: Start time string, e.g. "9:00" (optional)
    ///   - firstClassRoom: Room number (optional)
    func scheduleNightly(
        dayCode: String,
        firstClassName: String = "",
        firstClassTime: String = "",
        firstClassRoom: String = ""
    ) {
        guard NotificationSettings.isEnabled else {
            cancelNightlyNotifications()
            cancelMorningNotifications()
            return
        }

        guard !dayCode.isEmpty && dayCode != "Unknown" else { return }

        let fancy       = fancyDayName(dayCode)
        let formatter   = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let today       = formatter.string(from: Date())

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

        let selectedTime    = NotificationSettings.time
        let timeComponents  = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        var triggerComps    = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        triggerComps.hour   = timeComponents.hour
        triggerComps.minute = timeComponents.minute
        triggerComps.second = 0

        // Push to tomorrow if time already passed today
        if let t = Calendar.current.date(from: triggerComps), t <= Date() {
            let tmrw = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            triggerComps = Calendar.current.dateComponents([.year, .month, .day], from: tmrw)
            triggerComps.hour   = timeComponents.hour
            triggerComps.minute = timeComponents.minute
            triggerComps.second = 0
        }

        let eveningTrigger  = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let eveningID        = "\(nightlyIDPrefix)-\(today)"
        let eveningRequest   = UNNotificationRequest(identifier: eveningID,
                                                     content: eveningContent,
                                                     trigger: eveningTrigger)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [eveningID])
        UNUserNotificationCenter.current().add(eveningRequest) { err in
            if let err { print("❌ Evening notification error: \(err)") }
        }

        // ── Morning notification (10 min before first class) ──────────
        if !firstClassName.isEmpty, !firstClassTime.isEmpty {
            scheduleMorningAlert(
                className:    firstClassName,
                classTimeStr: firstClassTime,
                classRoom:    firstClassRoom,
                targetDate:   Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
                todayKey:     today
            )
        }
    }

    // MARK: - Morning alert

    private func scheduleMorningAlert(
        className: String,
        classTimeStr: String,
        classRoom: String,
        targetDate: Date,
        todayKey: String
    ) {
        // Parse "H:MM" into hour + minute
        let parts = classTimeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var hour   = parts[0]
        let minute = parts[1]
        // Mirror Time struct's AM/PM fix: times < 7 are PM
        if hour < 7 { hour += 12 }

        // 10 minutes before class
        var alertMin  = minute - 10
        var alertHour = hour
        if alertMin < 0 {
            alertMin  += 60
            alertHour -= 1
        }
        guard alertHour >= 0 else { return }

        var triggerComps  = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        triggerComps.hour   = alertHour
        triggerComps.minute = alertMin
        triggerComps.second = 0

        // Don't schedule if already in the past
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

        let trigger  = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let id       = "\(morningIDPrefix)-\(todayKey)"
        let request  = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().add(request) { err in
            if let err { print("❌ Morning notification error: \(err)") }
        }
    }

    // MARK: - Cancel

    func cancelNightlyNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(self.nightlyIDPrefix) }
                .map    { $0.identifier }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    func cancelMorningNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(self.morningIDPrefix) }
                .map    { $0.identifier }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    func cleanupExpiredNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let now = Date()
            let expiredIDs: [String] = requests.compactMap { req in
                guard req.identifier.hasPrefix(self.nightlyIDPrefix) ||
                      req.identifier.hasPrefix(self.morningIDPrefix),
                      let trigger = req.trigger as? UNCalendarNotificationTrigger,
                      let next    = trigger.nextTriggerDate(),
                      next < now
                else { return nil }
                return req.identifier
            }
            if !expiredIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: expiredIDs)
            }
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
                NotificationManager.shared.cancelNightlyNotifications()
                NotificationManager.shared.cancelMorningNotifications()
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
