//
//  AuthenticationView.swift
//  Schedule
//

import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var isSignUp = false
    @State private var showOnboarding = false
    @State private var classNamesFromOnboarding: [String] = []

    private var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
    }

    var body: some View {
        Group {
            if authManager.user != nil {
                ContentView(onboardingClassNames: classNamesFromOnboarding)
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
        // Onboarding overlay — shown after policy is accepted and user is signed in
        .onChange(of: authManager.user != nil) { _, isSignedIn in
            if isSignedIn && shouldShowOnboarding {
                // Small delay so ContentView has time to appear first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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

                OnboardingView(isPresented: $showOnboarding) { names in
                    classNamesFromOnboarding = names
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(101)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showOnboarding)
    }
}

