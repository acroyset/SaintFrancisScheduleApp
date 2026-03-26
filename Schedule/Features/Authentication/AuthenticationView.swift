//
//  AuthenticationView.swift
//  Schedule
//

import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var isSignUp = false
    @State private var showOnboarding = false
    @State private var classesFromOnboarding: [ClassItem] = []

    var body: some View {
        Group {
            if authManager.user != nil {
                ContentView(onboardingClasses: classesFromOnboarding)
                    .overlay(UpdatePromptView())
                    .environmentObject(authManager)
            } else {
                if isSignUp {
                    SignUpView(authManager: authManager, isSignUp: $isSignUp)
                } else {
                    SignInView(authManager: authManager, isSignUp: $isSignUp)
                }
            }
        }
        // Privacy policy sheet
        .sheet(isPresented: $authManager.needsPolicyAcceptance) {
            PolicyConsentSheet(
                authManager: authManager,
                isRenewal: authManager.user != nil
            )
        }
        // Use user?.id so the onChange fires reliably for any account transition,
        // including sign-out → new account (nil → id1 → nil → id2).
        .onChange(of: authManager.user?.id) { _, userId in
            guard userId != nil else { return }
            // Small delay lets ContentView settle before presenting onboarding
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let hasCompleted = UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
                if !hasCompleted {
                    showOnboarding = true
                }
            }
        }
        .overlay {
            if showOnboarding {
                // Dimmed backdrop
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(100)

                OnboardingView(isPresented: $showOnboarding) { items in
                    classesFromOnboarding = items
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(101)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showOnboarding)
    }
}
