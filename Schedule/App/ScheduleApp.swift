//
//  ScheduleApp.swift
//  Schedule
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import FirebasePerformance
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        FirebaseConfiguration.shared.setLoggerLevel(.min)
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Performance.sharedInstance().isDataCollectionEnabled = true
        logFirebaseDiagnostics()
        
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        
        return true
    }

    private func logFirebaseDiagnostics() {
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let app = FirebaseApp.app()
        let googleAppID = app?.options.googleAppID ?? "nil"
        let projectID = app?.options.projectID ?? "nil"
        let analyticsEnabled = Analytics.appInstanceID() != nil
        let performanceEnabled = Performance.sharedInstance().isDataCollectionEnabled

        print(
            """
            [Firebase] bundleID=\(bundleID)
            [Firebase] googleAppID=\(googleAppID)
            [Firebase] projectID=\(projectID)
            [Firebase] analyticsAppInstanceIDPresent=\(analyticsEnabled)
            [Firebase] performanceCollectionEnabled=\(performanceEnabled)
            """
        )
    }
}

@main
struct ScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    let notificationDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        ScheduleBackgroundManager.shared.registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            AuthenticationView()
        }
    }
}
