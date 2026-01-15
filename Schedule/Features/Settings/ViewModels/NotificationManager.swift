//
//  NotificationManager.swift
//  Schedule
//
//  Created by Andreas Royset on 12/2/25.
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
    private let notificationIDPrefix = "nightly"
    
    func scheduleNightly(dayCode: String) {
        guard NotificationSettings.isEnabled else {
            cancelNightlyNotifications()
            return
        }
        
        guard !dayCode.isEmpty && dayCode != "Unknown" else {
            print("⚠️ Notification: Invalid day code provided")
            return
        }
        
        let fancy = fancyDayName(dayCode)
        
        let content = UNMutableNotificationContent()
        content.title = "Daily Update"
        content.body = "Tomorrow is \(fancy)"
        content.sound = .default
        
        // Generate unique ID based on date to prevent duplicates
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let today = formatter.string(from: Date())
        let id = "\(notificationIDPrefix)-\(today)"
        
        // Calculate tomorrow's date for the notification
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else {
            print("❌ Notification: Failed to calculate tomorrow")
            return
        }
        
        // Get user-selected time
        let selectedTime = NotificationSettings.time
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        
        // Create date components for tomorrow at the selected time
        var tomorrowComponents = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        tomorrowComponents.hour = timeComponents.hour
        tomorrowComponents.minute = timeComponents.minute
        tomorrowComponents.second = 0
        
        // Verify the trigger time is in the future
        guard let triggerDate = Calendar.current.date(from: tomorrowComponents),
              triggerDate > Date() else {
            print("⚠️ Notification: Trigger time is in the past, skipping")
            return
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: tomorrowComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        // Remove any existing nightly notifications before adding new one
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        
        UNUserNotificationCenter.current().add(request) { err in
            if let err = err {
                print("❌ Notification scheduling failed: \(err)")
            } else {
                print("✅ Notification scheduled for tomorrow at \(tomorrowComponents.hour ?? 0):\(String(format: "%02d", tomorrowComponents.minute ?? 0))")
            }
        }
    }
    
    /// Cancel all nightly notifications
    func cancelNightlyNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let nightlyIDs = requests
                .filter { $0.identifier.hasPrefix(self.notificationIDPrefix) }
                .map { $0.identifier }
            
            if !nightlyIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: nightlyIDs)
                print("✅ Cancelled \(nightlyIDs.count) nightly notification(s)")
            }
        }
    }
    
    /// Remove old notifications from past dates (cleanup)
    func cleanupExpiredNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let now = Date()
            var expiredIDs: [String] = []
            
            for request in requests {
                if request.identifier.hasPrefix(self.notificationIDPrefix),
                   let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTrigger = trigger.nextTriggerDate(),
                   nextTrigger < now {
                    expiredIDs.append(request.identifier)
                }
            }
            
            if !expiredIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: expiredIDs)
                print("🧹 Cleaned up \(expiredIDs.count) expired notification(s)")
            }
        }
    }
}


class NotificationSettings {
    static let enabledKey = "NotificationsEnabled"
    static let timeKey = "NotificationTime" // stored as "HH:mm"
    
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue {
                // Re-request notification permissions if user re-enables
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if !granted {
                        print("⚠️ Notification permissions not granted")
                        UserDefaults.standard.set(false, forKey: enabledKey)
                    }
                }
            } else {
                // Cancel all notifications if disabled
                NotificationManager.shared.cancelNightlyNotifications()
            }
        }
    }
    
    static var time: Date {
        get {
            if let raw = UserDefaults.standard.string(forKey: timeKey) {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                return formatter.date(from: raw) ?? defaultTime
            }
            return defaultTime
        }
        set {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            UserDefaults.standard.set(formatter.string(from: newValue), forKey: timeKey)
        }
    }
    
    static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
    }
}
