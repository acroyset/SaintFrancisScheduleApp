//
//  ContentView.swift
//  Schedule
//

import SwiftUI
import Foundation
import UserNotifications

let version = "1.21"
let whatsNew = """
 - Custom schedules for special school days
 - Clearer campus map labels and room filtering
 - More reliable class, theme & event cloud sync
 - More accurate widgets and nightly notifications
 - Grade-tool, landscape & accessibility fixes
"""

enum ContentOverlayVisibility {
    static func showsCompactRefreshStatus(
        retryAttempt: Int,
        hasCachedSchedule: Bool,
        isCreationSheetPresented: Bool,
        isAddSelectorExpanded: Bool
    ) -> Bool {
        retryAttempt > 0
            && hasCachedSchedule
            && !isCreationSheetPresented
            && !isAddSelectorExpanded
    }

    static func showsScheduleLoadError(
        hasCachedSchedule: Bool,
        isCreationSheetPresented: Bool,
        isAddSelectorExpanded: Bool
    ) -> Bool {
        !hasCachedSchedule
            || (!isCreationSheetPresented && !isAddSelectorExpanded)
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var appStore = GlobalDataStore()
    @StateObject private var eventsManager = CustomEventsManager()
    @StateObject private var homeworkStore = HomeworkStore()
    @StateObject private var usageStats = UsageStatsStore.shared

    var onboardingClasses: [ClassItem] = []

    @State private var scrollTarget: Int? = nil
    @State private var showCalendarGrid = false
    @State private var whatsNewPopup = false
    @State private var lastSeenVersion: String = UserDefaults.standard.string(forKey: "LastSeenVersion") ?? ""
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "HasLaunchedBefore")

    @State private var addEvent = false
    @State private var addReminder = false
    @State private var addHomework = false
    @State private var isHomeAddSelectorExpanded = false
    @State private var homeAddSelectorHeight: CGFloat = 0
    @State private var window: Window = .Home
    @State private var openClassEditorFromMap = false
    @State private var isPortrait: Bool = !iPad
    @State private var tutorial = TutorialState.Hidden
    @State private var toolbarHeight: CGFloat = 0
    @State private var toolbarWidth: CGFloat = 0
    @State private var outgoingWindow: Window?
    @State private var pendingWindow: Window?
    @State private var pageSlideDirection: CGFloat = 1
    @State private var pageSlideProgress: CGFloat = 1
    @State private var pageSlideGeneration = 0
    @State private var showBackToSchoolReminderPrompt = false
    @State private var backToSchoolPromptOpensSettings = false
    @State private var showFirstDayClassUpdatePrompt = false

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let widgetRequestTicker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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

                VStack(spacing: window == .Map ? 0 : nil) {
                    if window != .Map {
                        topHeader
                    }

                    GeometryReader { geo in
                        ZStack {
                            if let outgoingWindow {
                                mainContentView(for: outgoingWindow)
                                    .environmentObject(eventsManager)
                                    .environmentObject(homeworkStore)
                                    .id(outgoingWindow.rawValue)
                                    .offset(
                                        x: -pageSlideDirection
                                            * pageSlideProgress
                                            * geo.size.width
                                    )
                            }

                            mainContentView(for: window)
                                .environmentObject(eventsManager)
                                .environmentObject(homeworkStore)
                                .id(window.rawValue)
                                .offset(
                                    x: outgoingWindow == nil
                                        ? 0
                                        : pageSlideDirection
                                            * (1 - pageSlideProgress)
                                            * geo.size.width
                                )
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(
                    .container,
                    edges: displaysFullScreenMap ? .all : []
                )
                .zIndex(0)

                ToolBar(
                    window: toolbarWindowBinding,
                    PrimaryColor: appStore.primaryColor,
                    SecondaryColor: appStore.secondaryColor,
                    TertiaryColor: appStore.tertiaryColor
                )
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                toolbarHeight = geo.size.height
                                toolbarWidth = geo.size.width
                            }
                            .onChange(of: geo.size) { _, newSize in
                                toolbarHeight = newSize.height
                                toolbarWidth = newSize.width
                            }
                    }
                )
                .zIndex(1000)

                overlays
            }
            .padding(.top, window == .Map ? 0 : 16)
            .padding(.horizontal, window == .Map ? 0 : 16)
            .background(appStore.tertiaryColor.ignoresSafeArea())
            .background(orientationReader)
            .animation(.easeInOut(duration: 0.1), value: appStore.dayCode)
            .onAppear(perform: handleAppear)
            .onChange(of: eventsManager.events, handleEventsChange)
            .onChange(of: appStore.data?.classes, handleClassesChange)
            .onChange(of: appStore.data?.isSecondLunch, handleLunchPreferenceChange)
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
                appStore.updateCurrentScheduleProgress()
                let currentTarget = appStore.scrollTargetForCurrentSchedule()
                if scrollTarget != currentTarget {
                    scrollTarget = currentTarget
                }
            }
            .onReceive(widgetRequestTicker) { _ in
                handleWidgetRefreshRequest()
                syncCurrentUsageSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .backToSchoolPromptEligibilityChanged)) { _ in
                handleBackToSchoolReminders()
            }
            .alert("School starts August 13", isPresented: $showBackToSchoolReminderPrompt) {
                if backToSchoolPromptOpensSettings {
                    Button("Open Settings") {
                        markBackToSchoolPromptShown()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } else {
                    Button("Turn On Reminders") {
                        markBackToSchoolPromptShown()
                        NotificationManager.shared.requestBackToSchoolAuthorizationAndSchedule()
                    }
                }
                Button("Not Now", role: .cancel) {
                    markBackToSchoolPromptShown()
                }
            } message: {
                Text("Want a reminder a few days before school starts so you can input your classes when you get them?")
            }
            .alert("Update Your Classes", isPresented: $showFirstDayClassUpdatePrompt) {
                Button("Update Classes") {
                    markFirstDayClassUpdatePromptShown()
                    openClassEditorFromMap = true
                    window = .ClassesView
                }
                Button("Not Now", role: .cancel) {
                    markFirstDayClassUpdatePromptShown()
                }
            } message: {
                Text("It’s the first day of school. Make sure your classes, teachers, and rooms are up to date.")
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
            if appStore.scheduleDict == nil {
                VStack(spacing: 8) {
                    SpinningGear(color: appStore.primaryColor)
                    Text("Loading schedule…")
                        .appThemeFont(.secondary, size: 13, weight: .medium)
                        .foregroundStyle(appStore.primaryColor.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ContentOverlayVisibility.showsCompactRefreshStatus(
                retryAttempt: appStore.scheduleRetryAttempt,
                hasCachedSchedule: true,
                isCreationSheetPresented: isCreationSheetPresented,
                isAddSelectorExpanded: isHomeAddSelectorExpanded
            ) {
                Label("Refreshing schedule…", systemImage: "arrow.clockwise")
                    .accessibilityIdentifier("schedule.refresh-status")
                    .appThemeFont(.secondary, size: 12, weight: .semibold)
                    .foregroundStyle(
                        appStore.tertiaryColor.maximumContrastTextColor()
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(appStore.tertiaryColor.opacity(0.94))
                            .overlay {
                                Capsule()
                                    .stroke(
                                        appStore.primaryColor.opacity(0.32),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .padding(.bottom, compactRefreshBottomPadding)
            }
        } else if let error = appStore.scheduleLoadError,
                  ContentOverlayVisibility.showsScheduleLoadError(
                    hasCachedSchedule: appStore.scheduleDict != nil,
                    isCreationSheetPresented: isCreationSheetPresented,
                    isAddSelectorExpanded: isHomeAddSelectorExpanded
                  ) {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .appThemeFont(.primary, size: 32)
                    .foregroundStyle(appStore.primaryColor.opacity(0.6))
                Text(error)
                    .accessibilityIdentifier("schedule.load-error")
                    .appThemeFont(.secondary, size: 14, weight: .medium)
                    .foregroundStyle(appStore.primaryColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry") {
                    appStore.retryScheduleLoad(events: eventsManager.events)
                }
                .buttonStyle(.borderedProminent)
                .tint(appStore.primaryColor)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(24)
            .frame(
                maxWidth: .infinity,
                maxHeight: appStore.scheduleDict == nil ? .infinity : nil
            )
            .padding(
                .bottom,
                appStore.scheduleDict == nil ? 0 : compactRefreshBottomPadding
            )
        }
    }

    private var isCreationSheetPresented: Bool {
        addEvent || addReminder || addHomework
    }

    private var compactRefreshBottomPadding: CGFloat {
        let defaultPadding = toolbarHeight + 8
        guard window == .Home,
              isPortrait,
              appStore.scheduleDict != nil else {
            return defaultPadding
        }

        let minimumSelectorHeight: CGFloat = iPad ? 86 : 64
        return toolbarHeight + max(homeAddSelectorHeight, minimumSelectorHeight) + 12
    }

    private var orientationReader: some View {
        GeometryReader { geo in
            OrientationReader(size: geo.size, onChange: updateOrientation(for:))
        }
    }

    private var toolbarWindowBinding: Binding<Window> {
        Binding(
            get: { pendingWindow ?? window },
            set: transitionToWindow
        )
    }

    private var displaysFullScreenMap: Bool {
        window == .Map || outgoingWindow == .Map
    }

    private var pageTransitionAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.88)
    }

    private func transitionToWindow(_ newWindow: Window) {
        if outgoingWindow != nil {
            pendingWindow = newWindow == window ? nil : newWindow
            return
        }

        guard newWindow != window else {
            pendingWindow = nil
            return
        }

        beginWindowTransition(to: newWindow)
    }

    private func beginWindowTransition(to newWindow: Window) {
        guard newWindow != window, outgoingWindow == nil else { return }

        pageSlideGeneration += 1
        let generation = pageSlideGeneration
        let previousWindow = window

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            pendingWindow = nil
            pageSlideDirection = newWindow.rawValue > previousWindow.rawValue ? 1 : -1
            pageSlideProgress = 0
            outgoingWindow = previousWindow
            window = newWindow
        }

        DispatchQueue.main.async {
            guard generation == pageSlideGeneration else { return }

            withAnimation(pageTransitionAnimation) {
                pageSlideProgress = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                guard generation == pageSlideGeneration else { return }

                var cleanupTransaction = Transaction()
                cleanupTransaction.animation = nil
                withTransaction(cleanupTransaction) {
                    outgoingWindow = nil
                }

                if let queuedWindow = pendingWindow,
                   queuedWindow != window {
                    DispatchQueue.main.async {
                        guard pendingWindow == queuedWindow,
                              outgoingWindow == nil else { return }

                        beginWindowTransition(to: queuedWindow)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mainContentView(for presentedWindow: Window) -> some View {
        switch presentedWindow {
        case .Home:
            HomeView(
                selectedDate: selectedDateBinding,
                showCalendarGrid: $showCalendarGrid,
                scrollTarget: $scrollTarget,
                addEvent: $addEvent,
                addReminder: $addReminder,
                addHomework: $addHomework,
                isAddSelectorExpanded: $isHomeAddSelectorExpanded,
                addSelectorHeight: $homeAddSelectorHeight,
                dayCode: appStore.dayCode,
                note: appStore.note,
                scheduleLines: appStore.scheduleLines,
                scheduleDict: appStore.scheduleDict,
                data: appStore.data,
                PrimaryColor: appStore.primaryColor,
                SecondaryColor: appStore.secondaryColor,
                TertiaryColor: appStore.tertiaryColor,
                toolbarHeight: toolbarHeight,
                toolbarWidth: toolbarWidth,
                isPortrait: isPortrait,
                onDatePick: { date in
                    appStore.applySelectedDate(date, events: eventsManager.events)
                    appStore.syncDerivedOutputs(events: eventsManager.events)
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
                isPortrait: isPortrait,
                openClassEditor: $openClassEditorFromMap
            )
            .environmentObject(homeworkStore)

        case .Map:
            MapView(
                data: appStore.data,
                PrimaryColor: appStore.primaryColor,
                SecondaryColor: appStore.secondaryColor,
                TertiaryColor: appStore.tertiaryColor,
                onEditClasses: {
                    openClassEditorFromMap = true
                    transitionToWindow(.ClassesView)
                }
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

    private func uploadUsageSession(_ session: UsageSessionRecord) {
        guard let userId = authManager.user?.id else { return }

        Task {
            do {
                try await CloudService().appendUsageSessionToCloud(session, for: userId)
            } catch {
                print("❌ Failed to append usage session: \(error)")
            }
        }
    }

    private func checkpointUsageSession() {
        guard let session = usageStats.pauseSession() else { return }
        uploadUsageSession(session)
    }

    private func syncCurrentUsageSession() {
        guard scenePhase == .active,
              let session = usageStats.snapshotSession() else { return }
        uploadUsageSession(session)
    }

    private func appendEndedUsageSession() {
        guard let session = usageStats.endSession() else { return }
        uploadUsageSession(session)
    }

    private func updateOrientation(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        isPortrait = size.height > size.width
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
            NotificationCenter.default.post(name: .dismissCourseAutocomplete, object: nil)
            showCalendarGrid = false
            UserDefaults.standard.set(version, forKey: "LastSeenVersion")
        }
    }

    private func handleAppear() {
        if !AppRuntime.isUITesting {
            usageStats.setUserScope(authManager.user?.id)
            if scenePhase == .active {
                usageStats.beginSession()
            }
            usageStats.setCurrentPage(usagePage(for: window))
            usageStats.setCurrentFeature(nil)
            syncCurrentUsageSession()
        }

        appStore.resetHomeDateToToday(events: eventsManager.events)
        appStore.loadData(
            authManager: authManager,
            eventsManager: eventsManager,
            onboardingClasses: onboardingClasses
        )
        if let classes = appStore.data?.classes {
            homeworkStore.reconcileClassReferences(with: classes)
        }
        appStore.syncDerivedOutputs(events: eventsManager.events)
        scrollTarget = appStore.scrollTargetForCurrentSchedule()

        if lastSeenVersion != version || isFirstLaunch {
            whatsNewPopup = true
        }
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        }

        if !AppRuntime.isUITesting {
            eventsManager.purgeExpiredReminders()
            appStore.updateNightlyNotification()
            handleWidgetRefreshRequest()
            handleBackToSchoolReminders()
            handleFirstDayClassUpdatePrompt()
        }
    }

    private func handleEventsChange(_: [CustomEvent], _: [CustomEvent]) {
        appStore.syncDerivedOutputs(events: eventsManager.events)
        scrollTarget = appStore.scrollTargetForCurrentSchedule()
    }

    private func handleClassesChange(_: [ClassItem]?, newClasses: [ClassItem]?) {
        guard let newClasses else { return }
        homeworkStore.reconcileClassReferences(with: newClasses)
        appStore.syncDerivedOutputs(events: eventsManager.events)
    }

    private func handleLunchPreferenceChange(_: [Bool]?, newValue: [Bool]?) {
        guard newValue != nil else { return }
        appStore.syncDerivedOutputs(events: eventsManager.events)
    }

    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        if AppRuntime.isUITesting {
            if newPhase == .active {
                appStore.updateCurrentScheduleProgress()
            }
            return
        }

        switch newPhase {
        case .active:
            usageStats.beginSession()
            usageStats.setCurrentPage(usagePage(for: window))
            syncCurrentUsageSession()
            appStore.retryScheduleLoad(events: eventsManager.events)
            appStore.updateCurrentScheduleProgress()
            appStore.updateNightlyNotification()
            eventsManager.purgeExpiredReminders()
            handleWidgetRefreshRequest()
            handleBackToSchoolReminders()
            handleFirstDayClassUpdatePrompt()
        case .background:
            appendEndedUsageSession()
            appStore.updateNightlyNotification()
        case .inactive:
            checkpointUsageSession()
        default:
            break
        }
    }

    private func handleBackToSchoolReminders() {
        NotificationManager.shared.scheduleBackToSchoolNotificationsIfAuthorized()
        NotificationManager.shared.cancelBackToSchoolFollowUpsAfterReturn()

        guard shouldOfferBackToSchoolReminderPrompt else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let canSchedule = NotificationManager.canScheduleBackToSchoolNotifications(with: settings.authorizationStatus)
            guard !canSchedule else { return }

            DispatchQueue.main.async {
                backToSchoolPromptOpensSettings = settings.authorizationStatus == .denied
                showBackToSchoolReminderPrompt = true
            }
        }
    }

    private var shouldOfferBackToSchoolReminderPrompt: Bool {
        guard UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") else { return false }
        guard !UserDefaults.standard.bool(forKey: BackToSchoolPromptStorage.reminderPrompt2026) else { return false }
        return Date() < Calendar.current.startOfDay(for: backToSchoolFirstDay)
    }

    private var backToSchoolFirstDay: Date {
        Calendar.current.date(
            from: DateComponents(
                calendar: Calendar.current,
                timeZone: TimeZone.current,
                year: 2026,
                month: 8,
                day: 13,
                hour: 0,
                minute: 0,
                second: 0
            )
        ) ?? .distantPast
    }

    private func markBackToSchoolPromptShown() {
        UserDefaults.standard.set(true, forKey: BackToSchoolPromptStorage.reminderPrompt2026)
    }

    private func handleFirstDayClassUpdatePrompt() {
        guard UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") else { return }
        guard !UserDefaults.standard.bool(forKey: BackToSchoolPromptStorage.firstDayClassUpdateHandled2026) else { return }
        guard Calendar.current.isDate(Date(), inSameDayAs: backToSchoolFirstDay) else { return }

        showFirstDayClassUpdatePrompt = true
    }

    private func markFirstDayClassUpdatePromptShown() {
        UserDefaults.standard.set(true, forKey: BackToSchoolPromptStorage.firstDayClassUpdateHandled2026)
    }

    private func handleWindowChange(oldWindow: Window, newWindow: Window) {
        guard oldWindow != newWindow else { return }
        usageStats.setCurrentPage(usagePage(for: newWindow))
        usageStats.setCurrentFeature(nil)
        syncCurrentUsageSession()
        withAnimation(.snappy) {
            showCalendarGrid = false
            isHomeAddSelectorExpanded = false
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
        if scenePhase == .active {
            usageStats.beginSession()
        }
        usageStats.setCurrentPage(usagePage(for: window))
        usageStats.setCurrentFeature(nil)
        syncCurrentUsageSession()
    }

    private func usagePage(for window: Window) -> UsagePage {
        switch window {
        case .Home:
            .home
        case .News:
            .news
        case .ClassesView:
            .classes
        case .Map:
            .map
        case .Profile:
            .profile
        }
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
