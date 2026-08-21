//
//  AuthenticationManager.swift
//  Schedule
//

import Firebase
import FirebaseAuth
import SwiftUI
import GoogleSignIn
import AuthenticationServices
import CryptoKit

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var needsPolicyAcceptance = false
    @Published var policyDenied = false
    @Published var isUsingDebugGuestSession = false

    // Delete-account re-auth flow
    @Published var needsReauthForDeletion = false
    @Published var reauthError = ""

    private var pendingPolicyUserId: String? = nil
    private var pendingPolicyIsNewUser: Bool = false
    let policyVersion = "2026-04-07"
    private lazy var dataManager = DataManager()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var isHandlingSignUp = false
    private let firebaseSignOut: () throws -> Void
    private let googleSignOut: () -> Void
    private let userDefaults: UserDefaults
    
    private var currentNonce: String?
    private var pendingAppleAuthorizationCode: String?

    init(
        startAuthStateListener: Bool = true,
        firebaseSignOut: @escaping () throws -> Void = { try Auth.auth().signOut() },
        googleSignOut: @escaping () -> Void = { GIDSignIn.sharedInstance.signOut() },
        userDefaults: UserDefaults = .standard
    ) {
        self.firebaseSignOut = firebaseSignOut
        self.googleSignOut = googleSignOut
        self.userDefaults = userDefaults

        if AppRuntime.isUITesting {
            isUsingDebugGuestSession = true
            userDefaults.set(true, forKey: "HasCompletedOnboarding")
            userDefaults.set(true, forKey: "HasLaunchedBefore")
            userDefaults.set(version, forKey: "LastSeenVersion")
            userDefaults.set(
                true,
                forKey: BackToSchoolPromptStorage.reminderPrompt2026
            )
            userDefaults.set(
                true,
                forKey: BackToSchoolPromptStorage.firstDayClassUpdateHandled2026
            )
            return
        }
        if startAuthStateListener {
            setupAuthStateListener()
        }
    }

    var hasActiveSession: Bool {
        user != nil || isUsingDebugGuestSession
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
    
    func signInWithApple(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = ""
        isHandlingSignUp = true
        defer { isHandlingSignUp = false }

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Unable to fetch identity token."
                isLoading = false
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)

                if authResult.additionalUserInfo?.isNewUser == true {
                    pendingAppleAuthorizationCode = appleIDCredential.authorizationCode
                        .flatMap { String(data: $0, encoding: .utf8) }
                    // Update display name if provided
                    if let fullName = appleIDCredential.fullName {
                        let displayName = [fullName.givenName, fullName.familyName]
                            .compactMap { $0 }
                            .joined(separator: " ")
                        if !displayName.isEmpty {
                            let changeRequest = authResult.user.createProfileChangeRequest()
                            changeRequest.displayName = displayName
                            try? await changeRequest.commitChanges()
                        }
                    }
                    pendingPolicyUserId = authResult.user.uid
                    pendingPolicyIsNewUser = true
                    needsPolicyAcceptance = true
                } else {
                    pendingAppleAuthorizationCode = nil
                    UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                    user = User(from: authResult.user)
                    await checkPolicyVersionForExistingUser(userId: authResult.user.uid)
                }
            } catch {
                errorMessage = handleAppleSignInError(error)
            }

        case .failure(let error):
            errorMessage = handleAppleSignInError(error)
        }
        isLoading = false
    }

    func prepareSignInWithApple() -> String? {
        do {
            let nonce = try randomNonceString()
            currentNonce = nonce
            return sha256(nonce)
        } catch {
            currentNonce = nil
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func prepareAppleReauthentication() -> String? {
        reauthError = ""
        do {
            let nonce = try randomNonceString()
            currentNonce = nonce
            return sha256(nonce)
        } catch {
            currentNonce = nil
            reauthError = error.localizedDescription
            return nil
        }
    }

    private func randomNonceString(length: Int = 32) throws -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = try (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    throw NSError(
                        domain: "AuthenticationManager",
                        code: Int(errorCode),
                        userInfo: [NSLocalizedDescriptionKey: "Unable to securely prepare Sign in with Apple. Please try again."]
                    )
                }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func handleAppleSignInError(_ error: Error) -> String {
        if let authorizationError = error as? ASAuthorizationError {
            switch authorizationError.code.rawValue {
            case ASAuthorizationError.canceled.rawValue:
                return "Apple Sign In was canceled."
            case ASAuthorizationError.failed.rawValue,
                 ASAuthorizationError.unknown.rawValue:
                return "Apple Sign In failed. Make sure the app target has the Sign in with Apple capability, the App ID for \(Bundle.main.bundleIdentifier ?? "this app") has Sign in with Apple enabled in Apple Developer, and the device or simulator is signed into iCloud."
            case ASAuthorizationError.invalidResponse.rawValue:
                return "Apple Sign In returned an invalid response. Please try again."
            case ASAuthorizationError.notHandled.rawValue:
                return "Apple Sign In could not be completed. Please try again."
            case ASAuthorizationError.notInteractive.rawValue:
                return "Apple Sign In is not available right now. Try again from an active app screen."
            case 1006:
                return "This Apple account is excluded for the requested sign-in. Try a different account or remove the excluded credential."
            case 1007:
                return "Apple credential import failed. Please try again."
            case 1008:
                return "Apple credential export failed. Please try again."
            case 1009:
                return "Use Sign in with Apple to continue with this account."
            case 1010:
                return "This device is not configured for passkey creation. Check your Apple account and passkey settings, then try again."
            default:
                return authorizationError.localizedDescription
            }
        }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            return "Apple Sign In succeeded with Apple but Firebase rejected it: \(nsError.localizedDescription)"
        }

        return error.localizedDescription
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
            pendingAppleAuthorizationCode = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func denyPrivacyPolicy() {
        policyDenied = true
        needsPolicyAcceptance = false
        if pendingPolicyIsNewUser {
            let targetUserID = pendingPolicyUserId
            let appleAuthorizationCode = pendingAppleAuthorizationCode
            Task {
                var revokedAppleToken = false
                do {
                    guard let firebaseUser = Auth.auth().currentUser else {
                        throw AccountDeletionIdentityError()
                    }
                    try Self.validateAccountDeletionIdentity(
                        targetUserID: targetUserID,
                        reauthenticatedUserID: firebaseUser.uid,
                        currentFirebaseUserID: Auth.auth().currentUser?.uid
                    )
                    if let appleAuthorizationCode {
                        try await Auth.auth().revokeToken(
                            withAuthorizationCode: appleAuthorizationCode
                        )
                        revokedAppleToken = true
                    }
                    try await self.dataManager.requestUserDataDeletion(
                        for: firebaseUser.uid
                    )
                    self.pendingPolicyUserId = nil
                    self.pendingPolicyIsNewUser = false
                    self.pendingAppleAuthorizationCode = nil
                    self.signOut()
                } catch {
                    // Do not sign out and orphan a newly-created Auth account
                    // when the durable request was not accepted (for example,
                    // if the fresh-auth window expired while the policy was
                    // open). Keep the user in the policy flow with all cloud
                    // data intact so they can retry or accept the policy.
                    self.errorMessage = "Account deletion did not start. Your account and data are still intact. Please try again."
                    self.policyDenied = false
                    self.needsPolicyAcceptance = true
                    self.pendingPolicyUserId = targetUserID
                    self.pendingPolicyIsNewUser = true
                    if revokedAppleToken {
                        self.pendingAppleAuthorizationCode = nil
                    } else {
                        self.pendingAppleAuthorizationCode = appleAuthorizationCode
                    }
                    print("⚠️ Could not request new-user deletion after policy denial: \(error)")
                }
            }
        } else {
            signOut()
            pendingPolicyUserId = nil
            pendingPolicyIsNewUser = false
            pendingAppleAuthorizationCode = nil
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try firebaseSignOut()
            googleSignOut()
            user = nil
            isUsingDebugGuestSession = false
            policyDenied = false
            // Reset all first-launch / onboarding flags so tutorial shows on next account
            userDefaults.set(false, forKey: "HasCompletedOnboarding")
            userDefaults.set(false, forKey: "HasLaunchedBefore")
            userDefaults.removeObject(forKey: "LastSeenVersion")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func continueInDebugGuestMode() {
        errorMessage = ""
        needsPolicyAcceptance = false
        policyDenied = false
        user = nil
        isUsingDebugGuestSession = true
        UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
    }
    #endif

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

    struct AccountDeletionIdentityError: LocalizedError, Equatable {
        var errorDescription: String? {
            "Account deletion stopped because the signed-in account changed. Please sign in again before retrying."
        }
    }

    static func validateAccountDeletionIdentity(
        targetUserID: String?,
        reauthenticatedUserID: String,
        currentFirebaseUserID: String?
    ) throws {
        guard let targetUserID,
              targetUserID == reauthenticatedUserID,
              targetUserID == currentFirebaseUserID else {
            throw AccountDeletionIdentityError()
        }
    }

    func deleteAccount() async {
        guard let targetUserID = user?.id,
              let firebaseUser = Auth.auth().currentUser else { return }
        do {
            try Self.validateAccountDeletionIdentity(
                targetUserID: targetUserID,
                reauthenticatedUserID: firebaseUser.uid,
                currentFirebaseUserID: Auth.auth().currentUser?.uid
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Reauthentication must precede the durable deletion request. The
        // backend will remove Firebase Auth first and Firestore second, so an
        // interruption can never leave a live account whose data was erased.
        reauthError = ""
        needsReauthForDeletion = true
    }

    func reauthWithPasswordAndDelete(password: String) async {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else { return }

        isLoading = true
        reauthError = ""

        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await firebaseUser.reauthenticate(with: credential)
            try await deleteReauthenticatedUser(firebaseUser)
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
            try await deleteReauthenticatedUser(firebaseUser)
            needsReauthForDeletion = false
            signOut()
        } catch {
            reauthError = error.localizedDescription
        }
        isLoading = false
    }

    func reauthWithAppleAndDelete(result: Result<ASAuthorization, Error>) async {
        guard let firebaseUser = Auth.auth().currentUser else {
            reauthError = "No signed-in account was found. Please sign in again."
            return
        }

        isLoading = true
        reauthError = ""
        defer {
            currentNonce = nil
            isLoading = false
        }

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8),
                  let authorizationCode = appleIDCredential.authorizationCode,
                  let authorizationCodeString = String(
                    data: authorizationCode,
                    encoding: .utf8
                  ) else {
                reauthError = "Unable to verify the Apple identity token. Please try again."
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            do {
                try await firebaseUser.reauthenticate(with: credential)
                // Apple requires the freshly issued authorization code to be
                // revoked when an account is deleted. Do this before the
                // durable deletion request so a revocation failure leaves the
                // Firebase account and Firestore data untouched.
                try await Auth.auth().revokeToken(
                    withAuthorizationCode: authorizationCodeString
                )
                try await deleteReauthenticatedUser(firebaseUser)
                needsReauthForDeletion = false
                signOut()
            } catch {
                reauthError = handleAppleSignInError(error)
            }

        case .failure(let error):
            reauthError = handleAppleSignInError(error)
        }
    }

    private func deleteReauthenticatedUser(_ firebaseUser: FirebaseAuth.User) async throws {
        let userId = user?.id
        try Self.validateAccountDeletionIdentity(
            targetUserID: userId,
            reauthenticatedUserID: firebaseUser.uid,
            currentFirebaseUserID: Auth.auth().currentUser?.uid
        )
        guard let userId else { throw AccountDeletionIdentityError() }

        // Firestore rules independently enforce a recent-authentication
        // window from the ID token's auth_time claim. Force a refresh so the
        // just-completed password/Google/Apple verification is represented in
        // the token used to create the deletion marker.
        _ = try await firebaseUser.getIDTokenResult(forcingRefresh: true)
        try await dataManager.requestUserDataDeletion(for: userId)
    }
}

enum AccountReauthenticationMethod: Equatable {
    case password
    case google
    case apple

    init(providerIDs: [String]) {
        if providerIDs.contains("apple.com") {
            self = .apple
        } else if providerIDs.contains("google.com") {
            self = .google
        } else {
            self = .password
        }
    }
}

// MARK: - User model

struct User {
    let id: String
    let email: String
    let displayName: String?

    init(id: String, email: String, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }

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
