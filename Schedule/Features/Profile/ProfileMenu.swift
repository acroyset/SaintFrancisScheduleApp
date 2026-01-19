import SwiftUI
import Foundation

struct ProfileMenu: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    @Binding var data: ScheduleData?
    @Binding var tutorial: TutorialState
    
    @Binding var PrimaryColor: Color
    @Binding var SecondaryColor: Color
    @Binding var TertiaryColor: Color
    var iPad: Bool
    
    @State private var showingDeleteAlert = false
    @State private var isLoadingSync = false
    @State private var isLoadingLoad = false
    @State private var syncMessage = ""
    @State private var showSyncMessage = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ScrollView{
                    
                    Color.clear.frame(height: iPad ? 60 : 50)
                    
                    if let user = authManager.user {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Signed in as:")
                                .font(.caption)
                                .foregroundStyle(TertiaryColor.highContrastTextColor())
                            
                            Text(user.displayName ?? "User")
                                .font(.headline)
                                .foregroundColor(PrimaryColor)
                            
                            Text(user.email)
                                .font(.caption)
                                .foregroundStyle(TertiaryColor.highContrastTextColor())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(SecondaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Sync Status Message
                    if showSyncMessage {
                        HStack {
                            Image(systemName: syncMessage.contains("✅") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(syncMessage.contains("✅") ? .green : .red)
                            Text(syncMessage.dropFirst())
                                .font(.footnote)
                                .foregroundStyle(TertiaryColor.highContrastTextColor())
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }
                    
                    // Manual Sync Button
                    Button {
                        sync()
                    } label: {
                        HStack {
                            if isLoadingSync {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Sync to Cloud")
                        }
                        .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                        .padding()
                        .background(SecondaryColor)
                        .foregroundColor(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isLoadingSync)
                    
                    Button {
                        load()
                    } label: {
                        HStack {
                            if isLoadingLoad {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Load from Cloud")
                        }
                        .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                        .padding()
                        .background(SecondaryColor)
                        .foregroundColor(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isLoadingLoad)
                    
                    Divider()
                    
                    Button {
                        tutorial = .Intro
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("Start Tutorial")
                                .font(.system(
                                    size: iPad ? 28 : 18,
                                    weight: .bold,
                                    design: .monospaced
                                ))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                        .background(SecondaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Spacer()
                    
                    // Danger Zone
                    VStack(spacing: 8) {
                        Text("Danger Zone")
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button {
                            showingDeleteAlert = true
                        } label: {
                            Text("Delete Account")
                                .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    Button {
                        authManager.signOut()
                        copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                            .padding()
                            .background(SecondaryColor)
                            .foregroundColor(PrimaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Color.clear.frame(height: iPad ? 60 : 50)
                }
                .mask{
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                
                }
            }
            
            VStack{
                if #available(iOS 26.0, *) {
                    Text("Profile")
                        .font(.system(
                            size: iPad ? 34 : 22,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(iPad ? 16 : 12)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(PrimaryColor)
                        .glassEffect()
                } else {
                    Text("Profile")
                        .font(.system(
                            size: iPad ? 34 : 22,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                }
                
                Spacer()
            }
        }
        .alert("Delete Account", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    deleteAccount()
                    copyText(from: "Resources/DefaultClasses.txt", to: "Resources/Classes.txt")
                }
            }
        } message: {
            Text("This will permanently delete your account and all data. This action cannot be undone.")
        }
    }
    
    private func sync() {
        guard let user = authManager.user,
              let scheduleData = data else {
            showMessage("❌ No data to sync")
            return
        }
        
        isLoadingSync = true
        showSyncMessage = false
        
        Task {
            do {
                let theme = ThemeColors(
                    primary: PrimaryColor.toHex() ?? "#00A5FFFF",
                    secondary: SecondaryColor.toHex() ?? "#00A5FF19",
                    tertiary: TertiaryColor.toHex() ?? "#FFFFFFFF"
                )
                
                try await dataManager.saveToCloud(
                    classes: scheduleData.classes,
                    theme: theme,
                    isSecondLunch: scheduleData.isSecondLunch,
                    for: user.id
                )
                
                await MainActor.run {
                    showMessage("✅ Synced successfully")
                    isLoadingSync = false
                }
            } catch {
                await MainActor.run {
                    showMessage(" Sync failed: \(error.localizedDescription)")
                    isLoadingSync = false
                }
                print("❌ Failed to sync: \(error)")
            }
        }
    }
    
    private func load() {
        guard let user = authManager.user else {
            showMessage("❌ Not signed in")
            return
        }
        
        isLoadingLoad = true
        showSyncMessage = false
        
        Task {
            do {
                let (cloudClasses, theme, isSecondLunch) = try await dataManager.loadFromCloud(for: user.id)
                
                await MainActor.run {
                    if !cloudClasses.isEmpty {
                        if var currentData = self.data {
                            currentData.classes = cloudClasses
                            currentData.isSecondLunch = isSecondLunch
                            self.data = currentData
                        }
                        overwriteClassesFile(with: cloudClasses)
                    }
                    
                    // Apply theme
                    self.PrimaryColor = Color(hex: theme.primary)
                    self.SecondaryColor = Color(hex: theme.secondary)
                    self.TertiaryColor = Color(hex: theme.tertiary)
                    
                    // Save theme locally
                    if let themeData = try? JSONEncoder().encode(theme) {
                        UserDefaults.standard.set(themeData, forKey: "LocalTheme")
                        SharedGroup.defaults.set(themeData, forKey: "ThemeColors")
                    }
                    
                    showMessage("✅ Loaded successfully")
                    isLoadingLoad = false
                }
            } catch {
                await MainActor.run {
                    showMessage(" Load failed: \(error.localizedDescription)")
                    isLoadingLoad = false
                }
                print("❌ Failed to load: \(error)")
            }
        }
    }
    
    private func deleteAccount() {
        guard let user = authManager.user else { return }
        
        Task {
            do {
                try await dataManager.deleteUserData(for: user.id)
                authManager.signOut()
            } catch {
                print("❌ Failed to delete account: \(error)")
            }
        }
    }
    
    private func showMessage(_ message: String) {
        syncMessage = message
        withAnimation {
            showSyncMessage = true
        }
        
        // Hide message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showSyncMessage = false
            }
        }
    }
}
