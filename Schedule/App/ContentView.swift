//
//  ContentView.swift
//  Schedule
//

import SwiftUI
import Foundation
import UserNotifications

let version = "1.17"
let whatsNew = " - Bug Fixes"

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var appStore = GlobalDataStore()
    @StateObject private var eventsManager = CustomEventsManager()
    @StateObject private var usageStats = UsageStatsStore.shared

    var onboardingClasses: [ClassItem] = []

    @State private var scrollTarget: Int? = nil
    @State private var showCalendarGrid = false
    @State private var whatsNewPopup = false
    @State private var lastSeenVersion: String = UserDefaults.standard.string(forKey: "LastSeenVersion") ?? ""
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "HasLaunchedBefore")

    @State private var addEvent = false
    @State private var addReminder = false
    @State private var window: Window = .Home
    @State private var isPortrait: Bool = !iPad
    @State private var tutorial = TutorialState.Hidden
    @State private var toolbarHeight: CGFloat = 0

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Background(
                    PrimaryColor: appStore.primaryColor,
                    SecondaryColor: appStore.secondaryColor,
                    TertiaryColor: appStore.tertiaryColor
                )
                .onTapGesture(perform: handleBackgroundTap)

                VStack {
                    topHeader
                    mainContentView
                        .environmentObject(eventsManager)
                }
                .zIndex(0)

                ToolBar(
                    window: $window,
                    PrimaryColor: appStore.primaryColor,
                    SecondaryColor: appStore.secondaryColor,
                    TertiaryColor: appStore.tertiaryColor
                )
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { toolbarHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newHeight in
                                toolbarHeight = newHeight
                            }
                    }
                )
                .zIndex(1000)

                overlays
            }
            .padding(.top)
            .padding(.horizontal)
            .background(appStore.tertiaryColor.ignoresSafeArea())
            .background(orientationReader)
            .animation(.easeInOut(duration: 0.1), value: appStore.dayCode)
            .onAppear(perform: handleAppear)
            .onChange(of: eventsManager.events, handleEventsChange)
            .onChange(of: appStore.dayCode, handleDayCodeChange)
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onChange(of: window, handleWindowChange)
            .onChange(of: onboardingClasses, handleOnboardingClassesChange)
            .onChange(of: appStore.primaryColor) { _, _ in appStore.saveTheme(authManager: authManager) }
            .onChange(of: appStore.secondaryColor) { _, _ in appStore.saveTheme(authManager: authManager) }
            .onChange(of: appStore.tertiaryColor) { _, _ in appStore.saveTheme(authManager: authManager) }
            .onChange(of: appStore.primaryFontChoice) { _, _ in appStore.saveTheme(authManager: authManager) }
            .onChange(of: appStore.secondaryFontChoice) { _, _ in appStore.saveTheme(authManager: authManager) }
            .onChange(of: NotificationSettings.isEnabled) { _, _ in appStore.updateNightlyNotification() }
            .onChange(of: NotificationSettings.time) { _, _ in appStore.updateNightlyNotification() }
            .onChange(of: authManager.user?.id, handleUserChange)
            .onReceive(ticker) { _ in
                eventsManager.purgeExpiredReminders()
                appStore.syncDerivedOutputs(events: eventsManager.events)
                scrollTarget = appStore.scrollTargetForCurrentSchedule()

                let now = Date()
                let lastWidgetCheck = SharedGroup.defaults.object(forKey: "LastWidgetCheck") as? Date ?? .distantPast
                if now.timeIntervalSince(lastWidgetCheck) > 30 {
                    SharedGroup.defaults.set(now, forKey: "LastWidgetCheck")
                    handleWidgetRefreshRequest()
                }
            }
        }
        .environment(\.appTheme, appStore.currentTheme)
    }

    @ViewBuilder
    private var topHeader: some View {
        Text("Version - \(version)\nBugs / Ideas - Email acroyset@gmail.com")
            .font(appStore.currentTheme.font(.secondary, size: iPad ? 12 : 10, weight: .regular))
            .foregroundStyle(appStore.tertiaryColor.highContrastTextColor())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .onTapGesture {
                withAnimation(.snappy) {
                    guard tutorial == .Hidden else { return }
                    showCalendarGrid = false
                    UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                }
            }
    }

    @ViewBuilder
    private var overlays: some View {
        if tutorial != .Hidden {
            TutorialView(
                tutorial: $tutorial,
                PrimaryColor: appStore.primaryColor,
                TertiaryColor: appStore.tertiaryColor,
                onStart: { window = .Home }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .zIndex(3000)
        }

        if whatsNewPopup {
            Color.black.opacity(0.0001)
                .ignoresSafeArea()
                .zIndex(2500)
                .onTapGesture {
                    withAnimation(.snappy) {
                        whatsNewPopup = false
                        UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                    }
                }

            WhatsNewView(
                whatsNewPopup: $whatsNewPopup,
                tutorial: $tutorial,
                PrimaryColor: appStore.primaryColor,
                SecondaryColor: appStore.secondaryColor,
                TertiaryColor: appStore.tertiaryColor,
                isFirstLaunch: isFirstLaunch,
                whatsNew: whatsNew
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .zIndex(3000)
        }

        if appStore.scheduleRetryAttempt > 0 {
            VStack(spacing: 8) {
                SpinningGear(color: appStore.primaryColor)
                Text("Loading...")
                    .appThemeFont(.secondary, size: 13, weight: .medium)
                    .foregroundStyle(appStore.primaryColor.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appStore.scheduleLoadError {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .appThemeFont(.primary, size: 32)
                    .foregroundStyle(appStore.primaryColor.opacity(0.6))
                Text(error)
                    .appThemeFont(.secondary, size: 14, weight: .medium)
                    .foregroundStyle(appStore.primaryColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var orientationReader: some View {
        GeometryReader { geo in
            OrientationReader(size: geo.size, onChange: updateOrientation(for:))
        }
    }

    @ViewBuilder
    private var mainContentView: some View {
        switch window {
        case .Home:
            HomeView(
                selectedDate: selectedDateBinding,
                showCalendarGrid: $showCalendarGrid,
                scrollTarget: $scrollTarget,
                addEvent: $addEvent,
                addReminder: $addReminder,
                dayCode: appStore.dayCode,
                note: appStore.note,
                scheduleLines: appStore.scheduleLines,
                scheduleDict: appStore.scheduleDict,
                data: appStore.data,
                PrimaryColor: appStore.primaryColor,
                SecondaryColor: appStore.secondaryColor,
                TertiaryColor: appStore.tertiaryColor,
                toolbarHeight: toolbarHeight,
                isPortrait: isPortrait,
                onDatePick: { date in
                    appStore.applySelectedDate(date, events: eventsManager.events)
                    scrollTarget = appStore.scrollTargetForCurrentSchedule()
                }
            )
            .onTapGesture {
                withAnimation(.snappy) {
                    showCalendarGrid = false
                    whatsNewPopup = false
                    tutorial = .Hidden
                    UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                }
            }

        case .News:
            NewsMenu(
                PrimaryColor: appStore.primaryColor,
                SecondaryColor: appStore.secondaryColor,
                TertiaryColor: appStore.tertiaryColor
            )

        case .ClassesView:
            ClassesView(
                data: Binding(
                    get: { (appStore.data ?? ScheduleData(classes: [], days: [])).normalized() },
                    set: { newValue in
                        appStore.data = newValue.normalized()
                        appStore.saveSchedule(authManager: authManager)
                    }
                ),
                PrimaryColor: appStore.primaryColor,
                SecondaryColor: appStore.secondaryColor,
                TertiaryColor: appStore.tertiaryColor,
                isPortrait: isPortrait
            )

        case .Profile:
            ProfileMenu(
                data: Binding(
                    get: { appStore.data },
                    set: { appStore.data = $0 }
                ),
                tutorial: $tutorial,
                PrimaryColor: Binding(
                    get: { appStore.primaryColor },
                    set: { appStore.primaryColor = $0 }
                ),
                SecondaryColor: Binding(
                    get: { appStore.secondaryColor },
                    set: { appStore.secondaryColor = $0 }
                ),
                TertiaryColor: Binding(
                    get: { appStore.tertiaryColor },
                    set: { appStore.tertiaryColor = $0 }
                ),
                primaryFontChoice: Binding(
                    get: { appStore.primaryFontChoice },
                    set: { appStore.primaryFontChoice = $0 }
                ),
                secondaryFontChoice: Binding(
                    get: { appStore.secondaryFontChoice },
                    set: { appStore.secondaryFontChoice = $0 }
                ),
                iPad: iPad,
                isPortrait: isPortrait
            )
        }
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { appStore.selectedDate },
            set: { appStore.selectedDate = $0 }
        )
    }

    private func appendEndedUsageSession() {
        guard let userId = authManager.user?.id,
              let session = usageStats.endSession() else { return }

        Task {
            do {
                try await CloudService().appendUsageSessionToCloud(session, for: userId)
            } catch {
                print("❌ Failed to append usage session: \(error)")
            }
        }
    }

    private func updateOrientation(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        isPortrait = size.height > size.width
    }

    private func saveEventsToCloud() {
        eventsManager.saveToCloud(using: authManager)
    }

    private func handleWidgetRefreshRequest() {
        WidgetManager.shared.handleRefreshRequestIfNeeded {
            await appStore.refreshAllData(
                authManager: authManager,
                events: eventsManager.events
            )
        }
    }

    private func handleBackgroundTap() {
        withAnimation(.snappy) {
            guard tutorial == .Hidden else { return }
            showCalendarGrid = false
            UserDefaults.standard.set(version, forKey: "LastSeenVersion")
        }
    }

    private func handleAppear() {
        usageStats.setUserScope(authManager.user?.id)
        if scenePhase == .active {
            usageStats.beginSession()
        }

        appStore.resetHomeDateToToday(events: eventsManager.events)
        appStore.loadData(
            authManager: authManager,
            eventsManager: eventsManager,
            onboardingClasses: onboardingClasses
        )
        scrollTarget = appStore.scrollTargetForCurrentSchedule()

        if lastSeenVersion != version || isFirstLaunch {
            whatsNewPopup = true
        }
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            appStore.syncDerivedOutputs(events: eventsManager.events)
        }

        eventsManager.purgeExpiredReminders()
        appStore.updateNightlyNotification()
    }

    private func handleEventsChange(_: [CustomEvent], _: [CustomEvent]) {
        appStore.syncDerivedOutputs(events: eventsManager.events)
        scrollTarget = appStore.scrollTargetForCurrentSchedule()
        saveEventsToCloud()
    }

    private func handleDayCodeChange(oldDay: String, newDay: String) {
        guard oldDay != newDay else { return }
        appStore.syncDerivedOutputs(events: eventsManager.events)
    }

    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            usageStats.beginSession()
            appStore.resetHomeDateToToday(events: eventsManager.events)
            appStore.syncDerivedOutputs(events: eventsManager.events)
            appStore.updateNightlyNotification()
            appStore.touchLastUpdated(authManager: authManager)
        case .background:
            appendEndedUsageSession()
            appStore.syncDerivedOutputs(events: eventsManager.events)
            appStore.updateNightlyNotification()
        case .inactive:
            appendEndedUsageSession()
        default:
            break
        }
    }

    private func handleWindowChange(oldWindow: Window, newWindow: Window) {
        guard oldWindow != newWindow else { return }
        withAnimation(.snappy) {
            showCalendarGrid = false
        }
    }

    private func handleOnboardingClassesChange(_: [ClassItem], newClasses: [ClassItem]) {
        guard !newClasses.isEmpty else { return }
        appStore.applyOnboardingClassesIfNeeded(newClasses)
        appStore.saveSchedule(authManager: authManager)
    }

    private func handleUserChange(_: String?, userId: String?) {
        appStore.handleUserChange(userId)
        usageStats.setUserScope(userId)
        appStore.touchLastUpdated(authManager: authManager)
    }

    private struct SpinningGear: View {
        let color: Color
        @State private var rotation: Double = 0

        var body: some View {
            Image(systemName: "gearshape.fill")
                .appThemeFont(.primary, size: 32)
                .foregroundStyle(color.opacity(0.6))
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        }
    }

    private struct OrientationReader: View {
        let size: CGSize
        let onChange: (CGSize) -> Void

        var body: some View {
            Color.clear
                .onAppear {
                    onChange(size)
                }
                .onChange(of: size) { _, newSize in
                    onChange(newSize)
                }
        }
    }
}
