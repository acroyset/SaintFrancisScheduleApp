//
//  ScheduleApp.swift
//  Schedule
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        FirebaseApp.configure()
        
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        
        return true
    }
}

@main
struct ScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    let notificationDelegate = NotificationDelegate()
    
    init() {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if !granted {print("❌ Notification Permission Denied")}
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
