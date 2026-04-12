//
//  Notifications.swift
//  Schedule
//
//  Created by Andreas Royset on 12/2/25.
//

import Foundation
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

struct NightlyNotificationContext {
    let dayCode: String
    let firstClassName: String
    let firstClassTime: String
    let firstClassRoom: String
}

enum NightlyNotificationBuilder {
    static func makeContext(
        scheduleDict: [String: [String]]?,
        data: ScheduleData?
    ) -> NightlyNotificationContext {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let key = ScheduleSelectionResolver.scheduleKey(for: tomorrow)
        let rawCode = (scheduleDict?[key] ?? ["", ""])[0]

        var firstName = ""
        var firstTime = ""
        var firstRoom = ""

        if let scheduleData = data, !rawCode.isEmpty {
            let dayMap = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
            if let dayIndex = dayMap[rawCode.lowercased()],
               scheduleData.days.indices.contains(dayIndex) {
                let day = scheduleData.days[dayIndex]
                for i in day.names.indices {
                    let nameRaw = day.names[i]
                    if nameRaw.hasPrefix("$"),
                       let classIndex = Int(nameRaw.dropFirst()),
                       (1...7).contains(classIndex),
                       classIndex <= scheduleData.classes.count {
                        let currentClass = scheduleData.classes[classIndex - 1]
                        if currentClass.name != "Period \(classIndex)" && currentClass.name != "None" {
                            firstName = currentClass.name
                            firstTime = day.startTimes[i].string()
                            firstRoom = (currentClass.room == "N" || currentClass.room.isEmpty) ? "" : currentClass.room
                            break
                        }
                    }
                }
            }
        }

        return NightlyNotificationContext(
            dayCode: rawCode,
            firstClassName: firstName,
            firstClassTime: firstTime,
            firstClassRoom: firstRoom
        )
    }
}
