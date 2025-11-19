//
//  AuthenticationView.swift
//  Schedule
//

import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var isSignUp = false

    var body: some View {
        Group {
            if authManager.user != nil {
                ContentView()
                    .environmentObject(authManager)
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
