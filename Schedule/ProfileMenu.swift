//
//  ProfileMenu.swift
//  Schedule
//
//  Created by Andreas Royset on 8/28/25.
//

import SwiftUI
import Foundation

struct ProfileMenu: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    @Binding var data: ScheduleData?
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var iPad: Bool
    
    @State private var showingDeleteAlert = false
    @State private var isLoading = false
    
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
                        .foregroundColor(.secondary)
                    
                    Text(user.displayName ?? "User")
                        .font(.headline)
                        .foregroundColor(PrimaryColor)
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
            
            // Manual Sync Button
            Button {
                syncClasses()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Sync Now")
                }
                .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                .padding()
                .background(SecondaryColor)
                .foregroundColor(PrimaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isLoading)
            
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
    
    private func syncClasses() {
        guard let user = authManager.user,
              let classes = data?.classes else { return }
        
        isLoading = true
        Task {
            do {
                try await dataManager.saveClasses(classes, for: user.id)
            } catch {
                print("Failed to sync classes: \(error)")
            }
            isLoading = false
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
