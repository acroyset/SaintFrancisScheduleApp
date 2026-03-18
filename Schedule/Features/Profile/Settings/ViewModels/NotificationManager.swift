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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let today = formatter.string(from: Date())
        let id = "\(notificationIDPrefix)-\(today)"
        
        let selectedTime = NotificationSettings.time
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        
        // Start with today
        var triggerComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        triggerComponents.hour = timeComponents.hour
        triggerComponents.minute = timeComponents.minute
        triggerComponents.second = 0
        
        // If that time has already passed today, push to tomorrow
        if let triggerDate = Calendar.current.date(from: triggerComponents), triggerDate <= Date() {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            triggerComponents = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            triggerComponents.hour = timeComponents.hour
            triggerComponents.minute = timeComponents.minute
            triggerComponents.second = 0
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        
        UNUserNotificationCenter.current().add(request) { err in
            if let err = err {
                print("❌ Notification scheduling failed: \(err)")
            } else {
                //print("✅ Notification scheduled for \(triggerComponents.month!)/\(triggerComponents.day!) at \(triggerComponents.hour ?? 0):\(String(format: "%02d", triggerComponents.minute ?? 0)) for \(dayCode)")
            }
        }
    }
    
    func cancelNightlyNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let nightlyIDs = requests
                .filter { $0.identifier.hasPrefix(self.notificationIDPrefix) }
                .map { $0.identifier }
            
            if !nightlyIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: nightlyIDs)
                //print("✅ Cancelled \(nightlyIDs.count) nightly notification(s)")
            }
        }
    }
    
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
                //print("🧹 Cleaned up \(expiredIDs.count) expired notification(s)")
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
                let center = UNUserNotificationCenter.current()
                let notificationDelegate = NotificationDelegate()
                center.delegate = notificationDelegate
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if !granted {print("❌ Notification Permission Denied")}
                } 
                
                ScheduleBackgroundManager.shared.scheduleNextNightlyRefresh()
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
