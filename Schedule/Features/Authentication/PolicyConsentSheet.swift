//
//  PolicyConsentSheet.swift
//  Schedule
//
//  Handles both first-time acceptance (new users) and renewal prompts
//  (existing users when the policy version has been updated).
//  Denying as a new user deletes the Firebase account.
//  Denying as an existing user signs them out.
//

import SwiftUI

struct PolicyConsentSheet: View {
    @ObservedObject var authManager: AuthenticationManager

    // True when this is a renewal prompt for an already-existing account
    var isRenewal: Bool = false

    @State private var showingDenyConfirm = false

    var body: some View {
        VStack(spacing: 16) {

            // Icon
            Image(systemName: isRenewal ? "arrow.clockwise.circle.fill" : "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
                .padding(.top, 8)

            // Title
            Text(isRenewal ? "Privacy Policy Updated" : "Privacy Policy")
                .font(.title2).bold()

            // Body
            Text(isRenewal
                 ? "Our Privacy Policy has been updated. Please review and accept the new version to continue using the app."
                 : "Please review and accept the Privacy Policy to finish creating your account.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .padding(.horizontal)

            // Open policy link
            Button("Open Privacy Policy") {
                if let url = URL(string: "https://sites.google.com/view/sf-schedule-privacy-policy/home") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(.blue)

            // Action buttons
            HStack(spacing: 12) {
                // Decline
                Button(role: .destructive) {
                    showingDenyConfirm = true
                } label: {
                    Text("Decline")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                // Accept
                Button {
                    Task { await authManager.acceptPrivacyPolicy() }
                } label: {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                        Text("Accept")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(authManager.isLoading)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(20)
        .presentationDetents([.height(isRenewal ? 420 : 460)])
        .interactiveDismissDisabled(true)   // Force explicit choice
        .confirmationDialog(
            isRenewal
                ? "Decline Policy Update?"
                : "Delete Account?",
            isPresented: $showingDenyConfirm,
            titleVisibility: .visible
        ) {
            Button(isRenewal ? "Sign Out" : "Delete My Account",
                   role: .destructive) {
                authManager.denyPrivacyPolicy()
            }
            Button("Go Back", role: .cancel) { }
        } message: {
            Text(isRenewal
                 ? "You will be signed out and cannot use the app until you accept the updated policy."
                 : "Your account will be permanently deleted. This cannot be undone.")
        }
    }
}
