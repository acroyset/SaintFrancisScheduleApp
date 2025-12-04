//
//  AuthenticationView.swift
//  Schedule
//

import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @EnvironmentObject var analyticsManager: AnalyticsManager
    @State private var isSignUp = false

    var body: some View {
        Group {
            if authManager.user != nil {
                ContentView()
                    .overlay(UpdatePromptView())
                    .environmentObject(authManager)
                    .environmentObject(analyticsManager)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        analyticsManager.startSession()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        analyticsManager.endSession()
                    }
            } else {
                if isSignUp {
                    SignUpView(authManager: authManager, isSignUp: $isSignUp)
                } else {
                    SignInView(authManager: authManager, isSignUp: $isSignUp)
                }
            }
        }
        .sheet(isPresented: $authManager.needsPolicyAcceptance) {
            PolicyConsentSheet(authManager: authManager)
        }
    }
}
