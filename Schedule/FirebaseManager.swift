//
//  FirebaseManager.swift
//  Schedule
//
//  Firebase Authentication and Data Management
//

import Firebase
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

extension UIApplication {
    var topViewController: UIViewController? {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

// MARK: - User Model
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

// MARK: - Authentication Manager
@MainActor
class AuthenticationManager: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage = ""

    // NEW: show a sheet the first time (new account only)
    @Published var needsPolicyAcceptance = false
    private var pendingPolicyUserId: String? = nil

    private let policyVersion = "2025-09-03"       // bump when policy changes
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
            
            // Update display name
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            user = User(from: result.user)
            copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")

            // Record acceptance at account creation time (you already gated with checkbox in UI)
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
                // First time: copy defaults and require policy acceptance once
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

    // Update signOut to also sign out Google
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
            // You might want to show a success message here
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Data Manager
@MainActor
class DataManager: ObservableObject {
    private let db = Firestore.firestore()
    
    func saveClasses(_ classes: [ClassItem], for userId: String) async throws {
        let classesData = classes.map { classItem in
            [
                "name": classItem.name,
                "teacher": classItem.teacher,
                "room": classItem.room
            ]
        }
        
        try await db.collection("users").document(userId).setData([
            "classes": classesData,
            "lastUpdated": Timestamp()
        ], merge: true)
    }
    
    func loadClasses(for userId: String) async throws -> [ClassItem] {
        let document = try await db.collection("users").document(userId).getDocument()
        
        guard let data = document.data(),
              let classesData = data["classes"] as? [[String: Any]] else {
            return []
        }
        
        return classesData.compactMap { classData in
            guard let name = classData["name"] as? String,
                  let teacher = classData["teacher"] as? String,
                  let room = classData["room"] as? String else {
                return nil
            }
            return ClassItem(name: name, teacher: teacher, room: room)
        }
    }
    
    func deleteUserData(for userId: String) async throws {
        try await db.collection("users").document(userId).delete()
    }
    
    func recordPolicyAcceptance(for userId: String, version: String) async throws {
            try await db.collection("users").document(userId).setData([
                "privacyPolicy": [
                    "accepted": true,
                    "version": version,
                    "timestamp": FieldValue.serverTimestamp()
                ]
            ], merge: true)
        }
}

// MARK: - Authentication Views
struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var isSignUp = false

    var body: some View {
        Group {
            if authManager.user != nil {
                ContentView()
                    .environmentObject(authManager)
            } else {
                if isSignUp {
                    SignUpView(authManager: authManager, isSignUp: $isSignUp)
                } else {
                    SignInView(authManager: authManager, isSignUp: $isSignUp)
                }
            }
        }
        .sheet(isPresented: $authManager.needsPolicyAcceptance) {
            PolicyConsentSheet(authManager: authManager)
        }
    }
}


struct SignInView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isSignUp: Bool
    
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false
    
    @State private var acceptedPolicy = false
    @State private var showPolicyWarning = false
    
    var body: some View {
        VStack(spacing: 24) {
            // App Title
            Text("Schedule App")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
                .padding(.top, 60)
            
            Text("Sign in to sync your classes")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Input Fields
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal, 24)
            
            // Error Message
            if !authManager.errorMessage.isEmpty {
                Text(authManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
            }
            
            if !authManager.errorMessage.isEmpty {
                Text(authManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
            }

            // Email/Password Sign In (unchanged)
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
            
            // Forgot Password
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
                        .font(.system(size: 28)) // Bigger "g" icon
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 50) // Slightly taller
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.6), lineWidth: 2.5) // Thicker border
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
            // Header
            Text("Create Account")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
                .padding(.top, 60)
            
            Text("Sign up to sync your classes")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Input Fields
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
            
            // Password validation
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
            
            // Error Message
            if !authManager.errorMessage.isEmpty {
                Text(authManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
            }
            
            HStack{
                
                Button(action: {
                    isChecked.toggle()
                    if (isChecked) {notChecked = false}
                }) {
                            Image(systemName: isChecked ? "checkmark.square" : "square")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(isChecked ? .blue : .gray)
                        }
                
                HStack(spacing: 0){
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
            
            if (notChecked){
                Text("Please Accept Privacy Policy")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Sign Up Button - FIXED
            Button {
                Task {
                    if (isChecked){
                        await authManager.signUp(email: email, password: password, displayName: displayName)
                    } else {
                        notChecked = true;
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
                .frame(maxWidth: .infinity, minHeight: 44) // Added minHeight for better touch area
                .padding()
                .background(isFormValid ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .disabled(authManager.isLoading || !isFormValid)
            
            // Sign In Link - FIXED
            HStack {
                Text("Already have an account?")
                    .foregroundColor(.secondary)
                Button {
                    isSignUp = false
                } label: {
                    Text("Sign In")
                        .foregroundColor(.blue)
                        .padding(.vertical, 8) // Added padding for better touch area
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
                    // If they cancel, you may optionally sign them out to avoid half-created state:
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
