//
//  AuthenticationManager.swift
//  Schedule
//

import Firebase
import FirebaseAuth
import SwiftUI
import GoogleSignIn

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var needsPolicyAcceptance = false
    @Published var policyDenied = false  // NEW: tracks if user denied policy

    private var pendingPolicyUserId: String? = nil
    private var pendingPolicyIsNewUser: Bool = false  // NEW: track if this is a new user awaiting policy
    let policyVersion = "2026-03-17"
    private let dataManager = DataManager()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var isHandlingSignUp = false

    init() {
        setupAuthStateListener()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }

            if let firebaseUser = firebaseUser {
                // Don't set user while a sign-up flow or policy acceptance is in progress
                guard !self.isHandlingSignUp && !self.needsPolicyAcceptance else { return }

                let appUser = User(from: firebaseUser)
                self.user = appUser

                // Check policy version for existing users on every sign-in
                Task {
                    await self.checkPolicyVersionForExistingUser(userId: appUser.id)
                }
            } else {
                self.user = nil
            }
        }
    }

    // MARK: - Policy Version Check (existing users)

    private func checkPolicyVersionForExistingUser(userId: String) async {
        // Skip if we're already showing policy UI (e.g. mid sign-up flow)
        guard !needsPolicyAcceptance else { return }

        do {
            let needsRenewal = try await dataManager.checkPolicyNeedsRenewal(
                for: userId,
                currentVersion: policyVersion
            )
            if needsRenewal {
                pendingPolicyUserId = userId
                pendingPolicyIsNewUser = false
                needsPolicyAcceptance = true
            }
        } catch {
            // Non-fatal — don't block the user if the check fails
            print("⚠️ Policy version check failed: \(error)")
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = ""
        isHandlingSignUp = true
        defer { isHandlingSignUp = false }

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()

            // The sign-up form has an explicit policy checkbox — record acceptance
            // directly instead of showing the sheet a second time.
            try await dataManager.recordPolicyAcceptance(for: result.user.uid, version: policyVersion)
            UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
            user = User(from: result.user)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = ""
        isHandlingSignUp = true
        defer { isHandlingSignUp = false }

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
            user = User(from: result.user)
            // Still run the policy version check for returning users
            await checkPolicyVersionForExistingUser(userId: result.user.uid)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Google Sign In

    func signInWithGoogle(presenting viewController: UIViewController) async {
        isLoading = true
        errorMessage = ""
        isHandlingSignUp = true
        defer { isHandlingSignUp = false }

        do {
            let g = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = g.user.idToken?.tokenString else {
                throw NSError(domain: "Auth", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"])
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: g.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)

            if authResult.additionalUserInfo?.isNewUser == true {
                // New Google user — need policy acceptance before fully signing in
                copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")
                pendingPolicyUserId = authResult.user.uid
                pendingPolicyIsNewUser = true
                needsPolicyAcceptance = true
                // Don't set self.user yet
            } else {
                UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                user = User(from: authResult.user)
                // Run policy version check manually since listener is bypassed
                await checkPolicyVersionForExistingUser(userId: authResult.user.uid)
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Accept Policy

    func acceptPrivacyPolicy() async {
        guard let uid = pendingPolicyUserId else {
            needsPolicyAcceptance = false
            return
        }

        isLoading = true

        do {
            try await dataManager.recordPolicyAcceptance(for: uid, version: policyVersion)

            needsPolicyAcceptance = false
            policyDenied = false

            // If this was a new user waiting for policy, now fully sign them in
            if pendingPolicyIsNewUser {
                if let firebaseUser = Auth.auth().currentUser {
                    user = User(from: firebaseUser)
                }
            }

            pendingPolicyUserId = nil
            pendingPolicyIsNewUser = false

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Deny Policy

    /// Called when a user declines the privacy policy.
    /// For new users this deletes their Firebase account entirely.
    /// For existing users (renewal) it signs them out.
    func denyPrivacyPolicy() {
        policyDenied = true
        needsPolicyAcceptance = false

        if pendingPolicyIsNewUser {
            // Delete the freshly-created Firebase account — they never agreed
            Task {
                do {
                    try await Auth.auth().currentUser?.delete()
                } catch {
                    print("⚠️ Could not delete new user account after policy denial: \(error)")
                }
                signOut()
            }
        } else {
            // Existing user refused renewal — sign them out
            signOut()
        }

        pendingPolicyUserId = nil
        pendingPolicyIsNewUser = false
    }

    // MARK: - Sign Out
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            user = nil
            policyDenied = false
            // Reset so a genuinely new account on this device sees onboarding
            UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
            // Delete the writable classes file — ensureWritableClassesFile()
            // will recreate it from the bundle default on next launch
            if let url = try? classesDocumentsURL() {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reset Password

    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = ""

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        guard let userId = user?.id else { return }
        do {
            try await dataManager.deleteUserData(for: userId)
            signOut()
        } catch {
            print("❌ Failed to delete account: \(error)")
        }
    }
}

// MARK: - User model

struct User {
    let id: String
    let email: String
    let displayName: String?

    init(from firebaseUser: FirebaseAuth.User) {
        self.id = firebaseUser.uid
        self.email = firebaseUser.email ?? ""
        self.displayName = firebaseUser.displayName
    }
}

// MARK: - UIApplication helper

extension UIApplication {
    var topViewController: UIViewController? {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
