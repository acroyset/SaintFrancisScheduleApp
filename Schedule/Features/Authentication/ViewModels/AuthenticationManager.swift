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
    
    private var pendingPolicyUserId: String? = nil
    private let policyVersion = "2025-09-03"
    private let dataManager = DataManager()
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        setupAuthStateListener()
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                self?.user = User(from: user)
            } else {
                self?.user = nil
            }
        }
    }
    
    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = ""
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            user = User(from: result.user)
            copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")

            try await dataManager.recordPolicyAcceptance(for: result.user.uid, version: policyVersion)

        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = ""
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            user = User(from: result.user)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signInWithGoogle(presenting viewController: UIViewController) async {
        isLoading = true
        errorMessage = ""

        do {
            let g = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = g.user.idToken?.tokenString else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"])
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: g.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            user = User(from: authResult.user)

            if authResult.additionalUserInfo?.isNewUser == true {
                copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")
                pendingPolicyUserId = authResult.user.uid
                needsPolicyAcceptance = true
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    
    func acceptPrivacyPolicy() async {
        guard let uid = pendingPolicyUserId else {
            needsPolicyAcceptance = false
            return
        }
        isLoading = true
        do {
            try await dataManager.recordPolicyAcceptance(for: uid, version: policyVersion)
            needsPolicyAcceptance = false
            pendingPolicyUserId = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            user = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
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
}

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

extension UIApplication {
    var topViewController: UIViewController? {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
