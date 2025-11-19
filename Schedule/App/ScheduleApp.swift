//
//  ScheduleApp.swift
//  Schedule
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct ScheduleApp: App {
    
    init() {
        FirebaseApp.configure()
        
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        } else {
            print("❌ Missing Firebase clientID – check GoogleService-Info.plist")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            AuthenticationView()
        }
    }
}
