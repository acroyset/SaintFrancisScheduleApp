//
//  SignInView.swift
//  Schedule
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    enum SignInStep {
        case options
        case emailChoice    // sign in vs create account
        case signIn
        case createAccount
    }

    @ObservedObject var authManager: AuthenticationManager
    

    @Environment(\.openURL) private var openURL

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showForgotPassword = false
    @State private var step: SignInStep = .options

    private var canSubmitSignIn: Bool {
        !email.isEmpty && !password.isEmpty && !authManager.isLoading
    }

    private var canSubmitCreate: Bool {
        !email.isEmpty && !displayName.isEmpty && password.count >= 6 && !authManager.isLoading
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    topMeta
                        .padding(.top, 18)
                        .padding(.horizontal, 24)
                    heroSection
                        .padding(.top, 32)
                        .padding(.bottom, 36)
                    authCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
        }
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
            Button("Send Reset Email") {
                Task { await authManager.resetPassword(email: email) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your email to receive a password reset link.")
        }
    }

    // MARK: - Top meta

    private var topMeta: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Version - \(version)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(.tertiaryLabel))
                Button {
                    if let url = URL(string: "mailto:acroyset@gmail.com") { openURL(url) }
                } label: {
                    Text("Bugs / Ideas → acroyset@gmail.com")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Text("Schedule")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color.blue, Color.cyan],
                                   startPoint: .leading, endPoint: .trailing)
                )

            Group {
                switch step {
                case .options:       Text("Welcome")
                case .emailChoice:   Text("Continue with email")
                case .signIn:        Text("Welcome back 👋")
                case .createAccount: Text("Create your account")
                }
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .animation(.easeInOut(duration: 0.2), value: step)
        }
    }

    // MARK: - Card shell

    private var authCard: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .options:
                    optionsContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                case .emailChoice:
                    emailChoiceContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                case .signIn:
                    signInContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                case .createAccount:
                    createAccountContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }

            if !authManager.errorMessage.isEmpty {
                Text(authManager.errorMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .clipped()
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: step)
    }

    // MARK: - Options (Google / Email / Apple)

    private var optionsContent: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 10)

            canvaStyleButton(icon: "google.logo", label: "Continue with Google", style: .google) {
                Task {
                    if let vc = UIApplication.shared.topViewController {
                        await authManager.signInWithGoogle(presenting: vc)
                    } else {
                        authManager.errorMessage = "Unable to find presenting view controller."
                    }
                }
            }
            .disabled(authManager.isLoading)

            canvaStyleButton(icon: "envelope.fill", label: "Continue with email", style: .standard) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    step = .emailChoice
                    authManager.errorMessage = ""
                }
            }

            appleCanvaButton

            #if DEBUG
            Divider().padding(.top, 6)

            canvaStyleButton(
                icon: "hammer.fill",
                label: "Continue in Debug Guest Mode",
                style: .standard
            ) {
                authManager.continueInDebugGuestMode()
            }
            .disabled(authManager.isLoading)
            #endif

            Divider().padding(.top, 6)

            Button {
                if let url = URL(string: "https://sites.google.com/view/sf-schedule-privacy-policy/home") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Privacy Policy")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Email choice (Sign In vs Create Account)

    private var emailChoiceContent: some View {
        VStack(spacing: 12) {
            backButton(to: .options)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                // Sign In — filled/primary
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        step = .signIn
                        authManager.errorMessage = ""
                    }
                } label: {
                    Text("Sign In")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(email.contains("@") ? Color.blue : Color.blue.opacity(0.35))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!email.contains("@"))
                .buttonStyle(.plain)

                // Create Account — outlined
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        step = .createAccount
                        authManager.errorMessage = ""
                    }
                } label: {
                    Text("Create Account")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(.systemBackground))
                        .foregroundColor(email.contains("@") ? .blue : .blue.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(email.contains("@") ? Color.blue.opacity(0.4) : Color.blue.opacity(0.15), lineWidth: 1)
                        )
                }
                .disabled(!email.contains("@"))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Sign In form

    private var signInContent: some View {
        VStack(spacing: 16) {
            backButton(to: .emailChoice)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 20)

            Button {
                Task { await authManager.signIn(email: email, password: password) }
            } label: {
                HStack(spacing: 10) {
                    if authManager.isLoading {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    }
                    Text("Sign In")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(canSubmitSignIn ? Color.blue : Color.blue.opacity(0.35))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canSubmitSignIn)
            .padding(.horizontal, 20)

            Button("Forgot password?") { showForgotPassword = true }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Create Account form

    private var createAccountContent: some View {
        VStack(spacing: 16) {
            backButton(to: .emailChoice)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                TextField("Your name", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password (6+ characters)", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 20)

            Button {
                Task { await authManager.signUp(email: email, password: password, displayName: displayName) }
            } label: {
                HStack(spacing: 10) {
                    if authManager.isLoading {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    }
                    Text("Create Account")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(canSubmitCreate ? Color.blue : Color.blue.opacity(0.35))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canSubmitCreate)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Shared back button

    private func backButton(to destination: SignInStep) -> some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    step = destination
                    authManager.errorMessage = ""
                    password = ""
                    displayName = ""
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("Back")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Canva-style button

    @ViewBuilder
    private func canvaStyleButton(
        icon: String,
        label: String,
        style: CanvaButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if icon == "google.logo" {
                        Text("G").font(.system(size: 20, weight: .black, design: .rounded))
                    } else {
                        Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(width: 28)
                .foregroundColor(style == .google ? .white : .primary)

                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(style == .google ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style == .google ? Color.blue : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style == .google ? Color.clear : Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var appleCanvaButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = authManager.prepareSignInWithApple()
        } onCompletion: { result in
            Task { await authManager.signInWithApple(result: result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(authManager.isLoading)
    }
}

private enum CanvaButtonStyle {
    case google
    case standard
}

#if DEBUG
#Preview("Sign In Page") {
    SignInView(authManager: AuthenticationManager())
}
#endif
