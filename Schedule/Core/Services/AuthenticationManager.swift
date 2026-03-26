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
    @Published var policyDenied = false

    // Delete-account re-auth flow
    @Published var needsReauthForDeletion = false
    @Published var reauthError = ""

    private var pendingPolicyUserId: String? = nil
    private var pendingPolicyIsNewUser: Bool = false
    let policyVersion = "2026-03-24"
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
                guard !self.isHandlingSignUp && !self.needsPolicyAcceptance else { return }
                let appUser = User(from: firebaseUser)
                self.user = appUser
                Task { await self.checkPolicyVersionForExistingUser(userId: appUser.id) }
            } else {
                self.user = nil
            }
        }
    }

    // MARK: - Policy Version Check

    private func checkPolicyVersionForExistingUser(userId: String) async {
        guard !needsPolicyAcceptance else { return }
        do {
            let needsRenewal = try await dataManager.checkPolicyNeedsRenewal(
                for: userId, currentVersion: policyVersion
            )
            if needsRenewal {
                pendingPolicyUserId = userId
                pendingPolicyIsNewUser = false
                needsPolicyAcceptance = true
            }
        } catch {
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
                copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")
                pendingPolicyUserId = authResult.user.uid
                pendingPolicyIsNewUser = true
                needsPolicyAcceptance = true
            } else {
                UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                user = User(from: authResult.user)
                await checkPolicyVersionForExistingUser(userId: authResult.user.uid)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Accept / Deny Policy

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
            if pendingPolicyIsNewUser, let firebaseUser = Auth.auth().currentUser {
                user = User(from: firebaseUser)
            }
            pendingPolicyUserId = nil
            pendingPolicyIsNewUser = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func denyPrivacyPolicy() {
        policyDenied = true
        needsPolicyAcceptance = false
        if pendingPolicyIsNewUser {
            Task {
                do { try await Auth.auth().currentUser?.delete() } catch {
                    print("⚠️ Could not delete new user after policy denial: \(error)")
                }
                signOut()
            }
        } else {
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
            // Reset all first-launch / onboarding flags so tutorial shows on next account
            UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
            UserDefaults.standard.set(false, forKey: "HasLaunchedBefore")
            UserDefaults.standard.removeObject(forKey: "LastSeenVersion")
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
        guard let userId = user?.id,
              let firebaseUser = Auth.auth().currentUser else { return }

        do {
            try await dataManager.deleteUserData(for: userId)
            try await firebaseUser.delete()
            signOut()
        } catch let error as NSError
            where error.domain == AuthErrorDomain
               && error.code   == AuthErrorCode.requiresRecentLogin.rawValue
        {
            reauthError = ""
            needsReauthForDeletion = true
        } catch {
            print("❌ Failed to delete account: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func reauthWithPasswordAndDelete(password: String) async {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else { return }

        isLoading = true
        reauthError = ""

        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await firebaseUser.reauthenticate(with: credential)
            if let userId = user?.id {
                try await dataManager.deleteUserData(for: userId)
            }
            try await firebaseUser.delete()
            needsReauthForDeletion = false
            signOut()
        } catch {
            reauthError = error.localizedDescription
        }
        isLoading = false
    }

    func reauthWithGoogleAndDelete(presenting viewController: UIViewController) async {
        guard let firebaseUser = Auth.auth().currentUser else { return }

        isLoading = true
        reauthError = ""

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
            try await firebaseUser.reauthenticate(with: credential)
            if let userId = user?.id {
                try await dataManager.deleteUserData(for: userId)
            }
            try await firebaseUser.delete()
            needsReauthForDeletion = false
            signOut()
        } catch {
            reauthError = error.localizedDescription
        }
        isLoading = false
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
