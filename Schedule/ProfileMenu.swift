//
//  ProfileMenu.swift
//  Schedule
//
//  Created by Andreas Royset on 8/28/25.
//

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
            
            // Sync Status
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.green)
                Text("Classes synced to cloud")
                    .font(.footnote)
                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                Spacer()
            }
            .padding(.vertical, 4)
            
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
                    Text("Load from cloud")
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
                
                // Delete Account Button - FIXED
                Button {
                    showingDeleteAlert = true
                } label: {
                    Text("Delete Account")
                        .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30) // Better touch area
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            // Sign Out Button - FIXED
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
              let classes = data?.classes else { return }
        
        isLoadingSync = true
        Task {
            do {
                let theme = ThemeColors(
                    primary: PrimaryColor.toHex() ?? "#000000FF",
                    secondary: SecondaryColor.toHex() ?? "#000000FF",
                    tertiary: TertiaryColor.toHex() ?? "#000000FF"
                )
                try await dataManager.saveToCloud(classes:classes, theme:theme, for: user.id)
            } catch {
                print("Failed to sync classes: \(error)")
            }
            isLoadingSync = false
        }
    }
    
    private func load() {
        guard let user = authManager.user else { return }
        
        isLoadingLoad = true
        Task {
            do {
                let (cloudClasses, theme) = try await dataManager.loadFromCloud(for: user.id)
                if !cloudClasses.isEmpty {
                    DispatchQueue.main.async {
                        if var currentData = self.data {
                            currentData.classes = cloudClasses
                            self.data = currentData
                        }
                        // Also save to local file as backup
                        overwriteClassesFile(with: cloudClasses)
                    }
                }
                
                PrimaryColor   = Color(hex: theme.primary)
                SecondaryColor = Color(hex: theme.secondary)
                TertiaryColor  = Color(hex: theme.tertiary)
            } catch {
                print("Failed to load classes: \(error)")
            }
            isLoadingLoad = false
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
}
