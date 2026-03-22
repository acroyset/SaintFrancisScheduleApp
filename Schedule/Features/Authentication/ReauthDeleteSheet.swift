//
//  ReauthDeleteSheet.swift
//  Schedule
//
//  Created by Andreas Royset on 3/21/26.
//
//
//  Shown when Firebase rejects an account deletion with
//  ERROR_REQUIRES_RECENT_LOGIN. The user re-authenticates here
//  and the deletion is retried automatically on success.
//

import SwiftUI

struct ReauthDeleteSheet: View {
    @ObservedObject var authManager: AuthenticationManager

    /// True when the account was signed in with Google (no password field shown).
    var isGoogleAccount: Bool

    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
                .padding(.top, 8)

            Text("Confirm Your Identity")
                .font(.title2).bold()

            Text("For your security, please verify your identity before we permanently delete your account.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .padding(.horizontal)

            if !authManager.reauthError.isEmpty {
                Text(authManager.reauthError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isGoogleAccount {
                // Google re-auth
                Button {
                    Task {
                        if let vc = UIApplication.shared.topViewController {
                            await authManager.reauthWithGoogleAndDelete(presenting: vc)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if authManager.isLoading {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                        } else {
                            Image(systemName: "g.circle.fill").font(.system(size: 24))
                            Text("Verify with Google").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(authManager.isLoading)
                .padding(.horizontal)

            } else {
                // Email/password re-auth
                SecureField("Enter your password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                Button(role: .destructive) {
                    Task { await authManager.reauthWithPasswordAndDelete(password: password) }
                } label: {
                    HStack {
                        if authManager.isLoading {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                        } else {
                            Text("Verify & Delete Account").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding()
                    .background(password.isEmpty ? Color.gray : Color.red)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(password.isEmpty || authManager.isLoading)
                .padding(.horizontal)
            }

            Button("Cancel") {
                authManager.needsReauthForDeletion = false
                authManager.reauthError = ""
            }
            .foregroundColor(.secondary)
            .padding(.bottom, 8)
        }
        .padding(20)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(authManager.isLoading)
    }
}
