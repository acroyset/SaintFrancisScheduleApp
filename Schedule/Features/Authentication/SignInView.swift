//
//  SignInView.swift
//  Schedule
//

import SwiftUI

struct SignInView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isSignUp: Bool
    
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Schedule App")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
                .padding(.top, 60)
            
            Text("Sign in to sync your classes")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal, 24)
            
            if !authManager.errorMessage.isEmpty {
                Text(authManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
            }
            
            Button {
                Task {
                    await authManager.signIn(email: email, password: password)
                }
            } label: {
                HStack {
                    if authManager.isLoading { ProgressView().progressViewStyle(.circular) }
                    else { Text("Sign In").fontWeight(.semibold) }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
            
            Button { showForgotPassword = true } label: {
                Text("Forgot Password?").foregroundColor(.blue).padding(.vertical, 8)
            }

            Button {
                Task {
                    if let vc = UIApplication.shared.topViewController {
                        await authManager.signInWithGoogle(presenting: vc)
                    } else {
                        authManager.errorMessage = "Unable to find a presenting view controller."
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 28))
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.6), lineWidth: 2.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .disabled(authManager.isLoading)

            HStack {
                Text("Don't have an account?").foregroundColor(.secondary)
                Button { isSignUp = true } label: {
                    Text("Sign Up").foregroundColor(.blue).padding(.vertical, 8)
                }
            }

            Spacer()
        }
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $email)
            Button("Send Reset Email") { Task { await authManager.resetPassword(email: email) } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Enter your email to receive a password reset link.") }
    }
}
