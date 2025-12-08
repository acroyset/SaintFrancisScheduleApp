//
//  ScheduleApp.swift
//  Schedule
//

import SwiftUI
import FirebaseCore
import GoogleSignIn


@main
struct ScheduleApp: App {
    let notificationDelegate = NotificationDelegate()
    
    init() {
        let center = UNUserNotificationCenter.current()
        
            center.delegate = notificationDelegate

            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if !granted {
                    print("❌ Notification Permission Denied")
                }
            }
        
        FirebaseApp.configure()
        
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        } else {
            print("❌ Missing Firebase clientID – check GoogleService-Info.plist")
        }
        
        ScheduleBackgroundManager.shared.registerBackgroundTasks()
        ScheduleBackgroundManager.shared.scheduleNextNightlyRefresh()
    }
    
    var body: some Scene {
        WindowGroup {
            AuthenticationView()
        }
    }
}
