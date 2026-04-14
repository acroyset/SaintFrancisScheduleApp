//
//  ProfileMenu.swift
//  Schedule
//

import SwiftUI
import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct ProfileMenu: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var eventsManager: CustomEventsManager
    private let persistence = CloudService()
    @Binding var data: ScheduleData?
    @Binding var tutorial: TutorialState
    
    @Binding var PrimaryColor: Color
    @Binding var SecondaryColor: Color
    @Binding var TertiaryColor: Color
    @Binding var primaryFontChoice: AppFontChoice
    @Binding var secondaryFontChoice: AppFontChoice
    var iPad: Bool
    var isPortrait: Bool
    
    @State private var showingDeleteAlert = false
    @State private var isSaving = false
    @State private var isLoading = false
    @State private var syncMessage = ""
    @State private var showSyncMessage = false
    @State private var showSettings = false
    @State private var showAllItems = false
    
    /// Detect Google accounts safely — only evaluated when the view
    /// is fully alive and authManager.user is already set.
    private var isGoogleAccount: Bool {
#if canImport(FirebaseAuth)
        guard authManager.user != nil else { return false }
        return Auth.auth().currentUser?.providerData
            .contains(where: { $0.providerID == "google.com" }) ?? false
#else
        return false
#endif
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ScrollView {
                    
                    Color.clear.frame(height: iPad ? 60 : 50)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            if let user = authManager.user {
                                Text("Signed in as:")
                                    .appThemeFont(.secondary, style: .caption)
                                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                                
                                Text(user.displayName ?? "User")
                                    .appThemeFont(.primary, style: .headline, weight: .semibold)
                                    .foregroundColor(PrimaryColor)
                                
                                Text(user.email)
                                    .appThemeFont(.secondary, style: .caption)
                                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                            } else {
                                Text("Debug Guest Mode")
                                    .appThemeFont(.primary, style: .headline, weight: .semibold)
                                    .foregroundColor(PrimaryColor)

                                Text("Working locally on this device")
                                    .appThemeFont(.secondary, style: .caption)
                                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                            }
                        }
                        
                        Spacer()
                        
                        VStack {
                            Button {
                                showSettings.toggle()
                            } label: {
                                Label(iPad ? "Settings" : "", systemImage: "gearshape.fill")
                                    .appThemeFont(.primary, style: .title)
                                    .foregroundStyle(PrimaryColor)
                            }
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Sync Status Message
                    if showSyncMessage {
                        HStack {
                            Image(systemName: syncMessage.contains("✅") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(syncMessage.contains("✅") ? .green : .red)
                            Text(syncMessage.dropFirst())
                                .appThemeFont(.secondary, style: .footnote)
                                .foregroundStyle(TertiaryColor.highContrastTextColor())
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }
                    
                    // Manual Save Button
                    Button {
                        save()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("Save")
                        }
                        .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                        .padding()
                        .background(SecondaryColor)
                        .foregroundColor(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isSaving)
                    
                    Button {
                        load()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text("Load")
                        }
                        .frame(maxWidth: .infinity, minHeight: iPad ? 44 : 30)
                        .padding()
                        .background(SecondaryColor)
                        .foregroundColor(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isLoading)
                    
                    Divider()
                    
                    Button {
                        tutorial = .Intro
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("Start Tutorial")
                                .appThemeFont(.secondary, size: iPad ? 28 : 18, weight: .bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                        .background(SecondaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        showAllItems = true
                    } label: {
                        HStack {
                            Image(systemName: "tray.full")
                            Text("View Events & Reminders")
                                .appThemeFont(.secondary, size: iPad ? 28 : 18, weight: .bold)
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
                    if authManager.user != nil {
                        VStack(spacing: 8) {
                            Text("Danger Zone")
                                .appThemeFont(.secondary, style: .caption)
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
                    }
                    
                    Button {
                        authManager.signOut()
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
                .mask {
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
            
            VStack {
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    Text("Profile")
                        .appThemeFont(.secondary, size: iPad ? 40 : 26, weight: .bold)
                        .padding(.vertical, iPad ? 20 : 14)
                        .padding(.horizontal, iPad ? 18 : 12)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(PrimaryColor)
                        .glassEffect()
                } else {
                    Text("Profile")
                        .appThemeFont(.secondary, size: iPad ? 40 : 26, weight: .bold)
                        .padding(.vertical, iPad ? 20 : 14)
                        .padding(.horizontal, iPad ? 18 : 12)
                        .foregroundStyle(PrimaryColor)
                }
                Spacer()
            }
        }
        .sheet(
            isPresented: $showSettings,
            onDismiss: { showSettings = false },
            content: {
                Settings(
                    PrimaryColor: $PrimaryColor,
                    SecondaryColor: $SecondaryColor,
                    TertiaryColor: $TertiaryColor,
                    primaryFontChoice: $primaryFontChoice,
                    secondaryFontChoice: $secondaryFontChoice,
                    isPortrait: isPortrait
                )
                .padding(.top, 32)
                .background(TertiaryColor)
            }
        )
        .sheet(isPresented: $showAllItems) {
            AllItemsView(
                scheduleDict: nil,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            .environmentObject(eventsManager)
        }
        .sheet(isPresented: $authManager.needsReauthForDeletion) {
            ReauthDeleteSheet(
                authManager: authManager,
                isGoogleAccount: isGoogleAccount
            )
        }
        .alert("Delete Account", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await authManager.deleteAccount() }
            }
        } message: {
            Text("This will permanently delete your account and all data. This action cannot be undone.")
        }
    }
    
    // MARK: - Save / Load
    
    private func save() {
        guard let scheduleData = data else {
            showMessage("❌ No data to save")
            return
        }
        
        isSaving = true
        showSyncMessage = false
        
        Task {
            do {
                let theme = ThemeColors(
                    primary: PrimaryColor.toHex() ?? "#00A5FFFF",
                    secondary: SecondaryColor.toHex() ?? "#00A5FF19",
                    tertiary: TertiaryColor.toHex() ?? "#FFFFFFFF",
                    primaryFont: primaryFontChoice,
                    secondaryFont: secondaryFontChoice
                )
                try await persistence.saveAppState(
                    classes: scheduleData.classes,
                    theme: theme,
                    isSecondLunch: scheduleData.isSecondLunch,
                    events: eventsManager.events,
                    userId: authManager.user?.id
                )
                await MainActor.run {
                    let message = authManager.user == nil
                        ? "✅ Saved on this device"
                        : "✅ Saved on this device and the cloud"
                    showMessage(message)
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    showMessage(" Save failed: \(error.localizedDescription)")
                    isSaving = false
                }
            }
        }
    }
    
    private func load() {
        isLoading = true
        showSyncMessage = false
        
        Task {
            do {
                guard let appState = try await persistence.loadAppState(
                    userId: authManager.user?.id,
                    parseClass: parseClass,
                    parseDays: parseDays
                ) else {
                    await MainActor.run {
                        showMessage("❌ No saved data found")
                        isLoading = false
                    }
                    return
                }

                await MainActor.run {
                    self.data = appState.schedule.normalizedData
                    let theme = ThemeColors(
                        primary: appState.schedule.theme.primary,
                        secondary: appState.schedule.theme.secondary,
                        tertiary: appState.schedule.theme.tertiary,
                        primaryFont: appState.schedule.theme.primaryFontChoice,
                        secondaryFont: appState.schedule.theme.secondaryFontChoice
                    )
                    self.PrimaryColor = Color(hex: theme.primary)
                    self.SecondaryColor = Color(hex: theme.secondary)
                    self.TertiaryColor = Color(hex: theme.tertiary)
                    self.primaryFontChoice = theme.primaryFontChoice
                    self.secondaryFontChoice = theme.secondaryFontChoice
                    self.eventsManager.events = appState.events
                    self.eventsManager.saveEvents()

                    let message = authManager.user == nil
                        ? "✅ Loaded from this device"
                        : "✅ Loaded from cloud or local backup"
                    showMessage(message)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    showMessage(" Load failed: \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }

    private func parseClass(_ line: String) -> ClassItem {
        let parts = line.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 4 { return ClassItem(name: parts[3], teacher: parts[1], room: parts[2]) }
        if parts.count == 3 { return ClassItem(name: parts[0], teacher: parts[1], room: parts[2]) }
        return ClassItem(name: "None", teacher: "None", room: "None")
    }

    private func parseDays(_ contents: String) -> [Day] {
        var days: [Day] = []
        var currentDay = Day()

        for raw in contents.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "$end" {
                days.append(currentDay)
                currentDay = Day()
                continue
            }

            let parts = line.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 3 {
                currentDay.names.append(parts[0])
                currentDay.startTimes.append(Time(parts[1]))
                currentDay.endTimes.append(Time(parts[2]))
            } else if let first = parts.first {
                currentDay.name = first
            }
        }

        return days
    }
    
    private func showMessage(_ message: String) {
        syncMessage = message
        withAnimation { showSyncMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showSyncMessage = false }
        }
    }
}

#if DEBUG
@MainActor
private func makePreviewAuthManager() -> AuthenticationManager {
    let manager = AuthenticationManager()
    manager.isUsingDebugGuestSession = true
    return manager
}

@MainActor
private func makePreviewEventsManager() -> CustomEventsManager {
    let manager = CustomEventsManager()
    manager.events = [
        CustomEvent(
            title: "Robotics Meeting",
            startTime: .from(hour: 15, minute: 30),
            endTime: .from(hour: 16, minute: 15),
            location: "Innovation Lab",
            note: "Bring prototype notes",
            color: "#4A90E2",
            repeatPattern: .none,
            kind: .event,
            applicableDays: ["04-13-26"]
        ),
        CustomEvent(
            title: "Turn in Chemistry Lab",
            startTime: .from(hour: 20, minute: 0),
            endTime: .from(hour: 20, minute: 15),
            note: "Upload PDF to Classroom",
            color: "#F97316",
            repeatPattern: .none,
            kind: .reminder,
            reminderOffsets: [.oneHour],
            applicableDays: ["04-13-26"]
        )
    ]
    return manager
}

private struct ProfileMenuPreviewWrapper: View {
    @State private var data: ScheduleData? = ScheduleData(
        classes: [
            ClassItem(name: "AP Biology", teacher: "Dr. Patel", room: "S201"),
            ClassItem(name: "English 2 Honors", teacher: "Ms. Lopez", room: "B104"),
            ClassItem(name: "Algebra 2", teacher: "Mr. Chen", room: "M301"),
            ClassItem(name: "US History", teacher: "Mr. Grant", room: "H210"),
            ClassItem(name: "Spanish 3", teacher: "Sra. Ruiz", room: "L112"),
            ClassItem(name: "Chemistry", teacher: "Dr. Kim", room: "S115"),
            ClassItem(name: "Design Lab", teacher: "Ms. Hart", room: "A008")
        ] + Array(ScheduleData.defaultClasses.dropFirst(7)),
        days: [],
        isSecondLunch: [false, false]
    ).normalized()
    @State private var tutorial: TutorialState = .Hidden
    @State private var primaryColor = Color.blue
    @State private var secondaryColor = Color.blue.opacity(0.12)
    @State private var tertiaryColor = Color.white
    @State private var primaryFontChoice: AppFontChoice = .rounded
    @State private var secondaryFontChoice: AppFontChoice = .rounded

    var body: some View {
        ProfileMenu(
            data: $data,
            tutorial: $tutorial,
            PrimaryColor: $primaryColor,
            SecondaryColor: $secondaryColor,
            TertiaryColor: $tertiaryColor,
            primaryFontChoice: $primaryFontChoice,
            secondaryFontChoice: $secondaryFontChoice,
            iPad: false,
            isPortrait: true
        )
        .environmentObject(makePreviewAuthManager())
        .environmentObject(makePreviewEventsManager())
        .background(tertiaryColor)
    }
}

#Preview("Profile Page") {
    ProfileMenuPreviewWrapper()
}
#endif
