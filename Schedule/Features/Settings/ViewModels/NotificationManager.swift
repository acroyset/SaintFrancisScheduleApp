//
//  File.swift
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
        "A1": "Anchor 1",
        "A2": "Anchor 2",
        "A3": "Anchor 3",
        "A4": "Anchor 4",
        "L1": "Late Start 1",
        "L2": "Late Start 2",
        "S1": "Special Schedule"
    ]

    return map[code.uppercased()] ?? code
}

class NotificationManager {
    static let shared = NotificationManager()
    
    func scheduleNightly(dayCode: String) {
        guard NotificationSettings.isEnabled else {
            return
        }
        
        let fancy = fancyDayName(dayCode)
        
        let content = UNMutableNotificationContent()
        content.title = "Daily Update"
        content.body = "Tomorrow is a \(fancy) Day."
        content.sound = .default
        
        // Unique ID per day
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let id = "nightly-\(formatter.string(from: Date()))"
        
        // Use user-selected time
        let selectedTime = NotificationSettings.time
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = Calendar.current.component(.hour, from: selectedTime)
        comps.minute = Calendar.current.component(.minute, from: selectedTime)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { err in
            if let err = err {
                print("❌ Failed:", err)
            }
        }
    }
}


class NotificationSettings {
    static let enabledKey = "NotificationsEnabled"
    static let timeKey = "NotificationTime" // stored as "HH:mm"
    
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
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
