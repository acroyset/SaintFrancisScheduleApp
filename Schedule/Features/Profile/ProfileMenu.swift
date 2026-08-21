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
    var scheduleCloudPhase: CloudSyncPhase
    var lastScheduleCloudSync: Date?
    var pendingScheduleCloudChanges: Int
    var syncCloudNow: () -> Void
    var iPad: Bool
    var isPortrait: Bool
    
    @State private var showingDeleteAlert = false
    @State private var isSaving = false
    @State private var isLoading = false
    @State private var syncMessage = ""
    @State private var showSyncMessage = false
    @State private var showSettings = false
    @State private var showCloud = false
    @State private var profileHeaderHeight: CGFloat = 0

    private var profileHeaderTopSpacing: CGFloat {
        max(profileHeaderHeight + (iPad ? 16 : 12), iPad ? 104 : 76)
    }

    private var readablePrimaryColor: Color {
        PrimaryColor.accessibleForegroundColor(
            against: SecondaryColor.composited(over: TertiaryColor)
        )
    }
    
    /// Choose a linked provider that can issue a fresh credential for account
    /// deletion. Apple accounts must not be sent through the password form.
    private var accountReauthenticationMethod: AccountReauthenticationMethod {
#if canImport(FirebaseAuth)
        guard authManager.user != nil else { return .password }
        let providerIDs = Auth.auth().currentUser?.providerData.map(\.providerID) ?? []
        return AccountReauthenticationMethod(providerIDs: providerIDs)
#else
        return .password
#endif
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ScrollView {
                    
                    Color.clear.frame(height: profileHeaderTopSpacing)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            if let user = authManager.user {
                                Text("Signed in as:")
                                    .appThemeFont(.secondary, style: .caption)
                                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                                
                                Text(user.displayName ?? "User")
                                    .appThemeFont(.primary, style: .headline, weight: .semibold)
                                    .foregroundColor(readablePrimaryColor)
                                
                                Text(user.email)
                                    .appThemeFont(.secondary, style: .caption)
                                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                            } else {
                                Text("Debug Guest Mode")
                                    .appThemeFont(.primary, style: .headline, weight: .semibold)
                                    .foregroundColor(readablePrimaryColor)

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
                                    .foregroundStyle(readablePrimaryColor)
                            }
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("profile.settings")
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        showCloud = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(readablePrimaryColor.opacity(0.12))
                                    .frame(width: 48, height: 48)
                                Image(systemName: cloudSummaryPhase.systemImage)
                                    .font(.system(size: 23, weight: .semibold))
                                    .foregroundStyle(cloudSummaryColor)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cloud")
                                    .appThemeFont(.primary, size: iPad ? 22 : 17, weight: .bold)
                                Text(cloudSummaryDetail)
                                    .appThemeFont(.secondary, size: iPad ? 15 : 12)
                                    .opacity(0.72)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .opacity(0.55)
                        }
                        .padding(14)
                        .background(SecondaryColor)
                        .foregroundColor(readablePrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("profile.cloud")
                    
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
                        .foregroundStyle(readablePrimaryColor)
                        .background(SecondaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    #if DEBUG
                    Button {
                        fatalError("Crashlytics test crash")
                    } label: {
                        Text("Crash")
                    }
                    #endif
                    
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
                            .foregroundColor(readablePrimaryColor)
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
                Group {
                    if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                        Text("Profile")
                            .appThemeFont(.secondary, size: iPad ? 40 : 26, weight: .bold)
                            .padding(.vertical, iPad ? 20 : 14)
                            .padding(.horizontal, iPad ? 18 : 12)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(PrimaryColor)
                            .glassEffect(.regular.tint(TertiaryColor.opacity(0.62)))
                    } else {
                        Text("Profile")
                            .appThemeFont(.secondary, size: iPad ? 40 : 26, weight: .bold)
                            .padding(.vertical, iPad ? 20 : 14)
                            .padding(.horizontal, iPad ? 18 : 12)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(PrimaryColor)
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { profileHeaderHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newHeight in
                                profileHeaderHeight = newHeight
                            }
                    }
                )
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
        .sheet(isPresented: $showCloud) {
            CloudSyncView(
                email: authManager.user?.email,
                schedulePhase: scheduleCloudPhase,
                eventsPhase: eventsManager.cloudSyncPhase,
                lastScheduleSync: lastScheduleCloudSync,
                lastEventsSync: eventsManager.lastCloudSyncDate,
                pendingScheduleChanges: pendingScheduleCloudChanges,
                classCount: data?.classes.filter {
                    !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && $0.name.caseInsensitiveCompare("None") != .orderedSame
                }.count ?? 0,
                eventCount: eventsManager.events.count,
                primaryColor: PrimaryColor,
                secondaryColor: SecondaryColor,
                backgroundColor: TertiaryColor,
                syncNow: syncCloudNow
            )
        }
        .sheet(isPresented: $authManager.needsReauthForDeletion) {
            ReauthDeleteSheet(
                authManager: authManager,
                method: accountReauthenticationMethod
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
        .onAppear {
            syncTrackedFeature()
        }
        .onChange(of: showSettings) { _, _ in
            syncTrackedFeature()
        }
        .onChange(of: showCloud) { _, _ in
            syncTrackedFeature()
        }
    }

    private var cloudSummaryPhase: CloudSyncPhase {
        guard authManager.user != nil else { return .disconnected }
        if case .failed(let message) = scheduleCloudPhase { return .failed(message) }
        if case .failed(let message) = eventsManager.cloudSyncPhase { return .failed(message) }
        if scheduleCloudPhase == .loading || eventsManager.cloudSyncPhase == .loading { return .loading }
        if scheduleCloudPhase == .pending || eventsManager.cloudSyncPhase == .pending { return .pending }
        return .synced
    }

    private var cloudSummaryDetail: String {
        authManager.user == nil ? "Sign in to sync across devices" : "\(cloudSummaryPhase.title) • Automatic"
    }

    private var cloudSummaryColor: Color {
        switch cloudSummaryPhase {
        case .disconnected: .secondary
        case .loading, .pending: .orange
        case .synced: .green
        case .failed: .red
        }
    }
    
    // MARK: - Save / Load
    
    private func save() {
        guard data != nil else {
            showMessage("❌ No data to save")
            return
        }
        
        isSaving = true
        showSyncMessage = false

        // This closure is owned by ContentView and routes through
        // GlobalDataStore and CustomEventsManager. Both managers validate the
        // active account's durable snapshot before touching local or cloud
        // data, so a corrupt activation cannot be saved as an empty account.
        syncCloudNow()
        let message = authManager.user == nil
            ? "✅ Saved on this device"
            : "✅ Sync requested"
        showMessage(message)
        isSaving = false
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

    private func syncTrackedFeature() {
        if showSettings || showCloud {
            UsageStatsStore.shared.setCurrentFeature(.settings)
        } else {
            UsageStatsStore.shared.setCurrentFeature(nil)
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
            scheduleCloudPhase: .synced,
            lastScheduleCloudSync: Date(),
            pendingScheduleCloudChanges: 0,
            syncCloudNow: {},
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
