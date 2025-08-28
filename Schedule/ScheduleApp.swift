//
//  ScheduleApp.swift
//  Schedule
//

import SwiftUI
import FirebaseCore

@main
struct ScheduleApp: App {
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            AuthenticationView()
                .preferredColorScheme(.light)
        }
    }
}
