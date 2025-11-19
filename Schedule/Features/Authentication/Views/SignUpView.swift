//
//  SignUpView.swift
//  Schedule
//

import SwiftUI

struct SignUpView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isSignUp: Bool
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isChecked = false
    @State private var notChecked = false
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !displayName.isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Create Account")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
                .padding(.top, 60)
            
            Text("Sign up to sync your classes")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 16) {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                
                SecureField("Password (6+ characters)", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal, 24)
            
            if !password.isEmpty && password.count < 6 {
                Text("Password must be at least 6 characters")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords don't match")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if !authManager.errorMessage.isEmpty {
                Text(authManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
            }
            
            HStack {
                Button(action: {
                    isChecked.toggle()
                    if isChecked { notChecked = false }
                }) {
                    Image(systemName: isChecked ? "checkmark.square" : "square")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(isChecked ? .blue : .gray)
                }
                
                HStack(spacing: 0) {
                    Text("Accept ")
                    Text("Privacy Policy")
                        .foregroundColor(.blue)
                        .underline()
                        .onTapGesture {
                            if let url = URL(string: "https://sites.google.com/view/sf-schedule-privacy-policy/home") {
                                UIApplication.shared.open(url)
                            }
                        }
                }
            }
            
            if notChecked {
                Text("Please Accept Privacy Policy")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button {
                Task {
                    if isChecked {
                        await authManager.signUp(email: email, password: password, displayName: displayName)
                    } else {
                        notChecked = true
                    }
                }
                copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")
            } label: {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding()
                .background(isFormValid ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .disabled(authManager.isLoading || !isFormValid)
            
            HStack {
                Text("Already have an account?")
                    .foregroundColor(.secondary)
                Button {
                    isSignUp = false
                } label: {
                    Text("Sign In")
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                }
            }
            
            Spacer()
        }
    }
}

struct PolicyConsentSheet: View {
    @ObservedObject var authManager: AuthenticationManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Privacy Policy")
                .font(.title2).bold()

            Text("Please review and accept the Privacy Policy to finish creating your account.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Open Privacy Policy") {
                if let url = URL(string: "https://sites.google.com/view/sf-schedule-privacy-policy/home") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(.blue)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    authManager.signOut()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }

                Button {
                    Task { await authManager.acceptPrivacyPolicy() }
                } label: {
                    Text("Accept")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .presentationDetents([.height(280)])
    }
}
