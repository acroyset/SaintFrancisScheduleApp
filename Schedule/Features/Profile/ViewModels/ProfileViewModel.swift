//
//  ProfileViewModel.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var isLoadingSync = false
    @Published var isLoadingLoad = false
    @Published var syncMessage = ""
    @Published var showSyncMessage = false
    @Published var showingDeleteAlert = false
    
    private let dataManager = DataManager()
    
    func sync(user: User, scheduleData: ScheduleData, primaryColor: Color, secondaryColor: Color, tertiaryColor: Color) async {
        isLoadingSync = true
        showSyncMessage = false
        
        do {
            let theme = ThemeColors(
                primary: primaryColor.toHex() ?? "#0000FFFF",
                secondary: secondaryColor.toHex() ?? "#0000FF19",
                tertiary: tertiaryColor.toHex() ?? "#FFFFFFFF"
            )
            
            try await dataManager.saveToCloud(
                classes: scheduleData.classes,
                theme: theme,
                isSecondLunch: scheduleData.isSecondLunch,
                for: user.id
            )
            
            showMessage("✅ Synced successfully")
            isLoadingSync = false
        } catch {
            showMessage(" Sync failed: \(error.localizedDescription)")
            isLoadingSync = false
        }
    }
    
    func load(user: User, onSuccess: @escaping ([ClassItem], ThemeColors, [Bool]) -> Void) async {
        isLoadingLoad = true
        showSyncMessage = false
        
        do {
            let (cloudClasses, theme, isSecondLunch) = try await dataManager.loadFromCloud(for: user.id)
            onSuccess(cloudClasses, theme, isSecondLunch)
            showMessage("✅ Loaded successfully")
            isLoadingLoad = false
        } catch {
            showMessage(" Load failed: \(error.localizedDescription)")
            isLoadingLoad = false
        }
    }
    
    func deleteAccount(user: User, authManager: AuthenticationManager) async {
        do {
            try await dataManager.deleteUserData(for: user.id)
            authManager.signOut()
        } catch {
            print("❌ Failed to delete account: \(error)")
        }
    }
    
    private func showMessage(_ message: String) {
        syncMessage = message
        withAnimation {
            showSyncMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                self.showSyncMessage = false
            }
        }
    }
}
