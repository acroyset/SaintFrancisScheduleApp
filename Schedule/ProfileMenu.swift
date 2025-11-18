import SwiftUI
import Foundation

func classesDocumentsURL() throws -> URL {
    let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return docs.appendingPathComponent("Classes.txt")
}

@discardableResult
func ensureWritableClassesFile() throws -> URL {
    let dst = try classesDocumentsURL()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dst.path) {
        if let src = Bundle.main.url(forResource: "Classes", withExtension: "txt") {
            try? fm.copyItem(at: src, to: dst)
        } else {
            try "".write(to: dst, atomically: true, encoding: .utf8)
        }
    }
    return dst
}

func overwriteClassesFile(with classes: [ClassItem]) {
    do {
        let url = try ensureWritableClassesFile()
        let text = classes.map { "\($0.name) - \($0.teacher) - \($0.room)" }
                          .joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        print("overwriteClassesFile error:", error)
    }
}

struct ProfileMenu: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    @Binding var data: ScheduleData?
    
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
        VStack(spacing: 12) {
            Text("Profile")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
            
            Divider()
            
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
                    Text(syncMessage)
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
                copyText(from: "DefaultClasses.txt", to: "Classes.txt")
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                    .padding()
                    .background(SecondaryColor)
                    .foregroundColor(PrimaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert("Delete Account", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    deleteAccount()
                    copyText(from: "DefaultClasses.txt", to: "Classes.txt")
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
                    primary: PrimaryColor.toHex() ?? "#0000FFFF",
                    secondary: SecondaryColor.toHex() ?? "#0000FF19",
                    tertiary: TertiaryColor.toHex() ?? "#FFFFFFFF"
                )
                
                print("🔄 Syncing theme: \(theme)")
                
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
                    showMessage("❌ Sync failed: \(error.localizedDescription)")
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
                    
                    print("✅ Loaded theme: \(theme)")
                }
            } catch {
                await MainActor.run {
                    showMessage("❌ Load failed: \(error.localizedDescription)")
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
                print("Failed to delete account: \(error)")
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
