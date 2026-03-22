//
//  ContentView.swift
//  Schedule
//

import SwiftUI
import Foundation
import UserNotifications

let version = "1.15"
let whatsNew = "- More Widgets!!!\n- Settings now in profile tab\n- Encrypted data storage for privacy\n- Bug Fixes"

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    @StateObject private var eventsManager = CustomEventsManager()

    @State private var themeDebounceTask: Task<Void, Never>?
    @State private var lastSavedTheme: ThemeColors?

    @State private var output = "Loading…"
    @State private var dayCode = ""
    @State private var note = ""
    @State var scheduleDict: [String: [String]]? = nil
    @State private var hasTriedFetchingSchedule = false
    @State private var scheduleLines: [ScheduleLine] = []
    @State private var data: ScheduleData? = nil
    var onboardingClasses: [ClassItem] = []
    @State private var selectedDate = Date()
    @State private var scrollTarget: Int? = nil
    @State private var showCalendarGrid = false
    @State private var whatsNewPopup = false
    @State private var lastSeenVersion: String = UserDefaults.standard.string(forKey: "LastSeenVersion") ?? ""
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
    @State private var scheduleLoadError: String? = nil
    @State private var scheduleRetryAttempt: Int = 0
    @State private var resetHomeScroll = false

    @State private var addEvent = false
    @State private var window: Window = Window.Home

    @State private var PrimaryColor: Color = .blue
    @State private var SecondaryColor: Color = .blue.opacity(0.1)
    @State private var TertiaryColor: Color = .primary

    @State private var isPortrait: Bool = !iPad
    @State private var hasLoadedFromCloud = false
    @State private var tutorial = TutorialState.Hidden

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Background(
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .onTapGesture {
                    withAnimation(.snappy) {
                        guard tutorial == .Hidden else { return }
                        showCalendarGrid = false
                        UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                    }
                }

                VStack {
                    topHeader
                    mainContentView
                        .environmentObject(eventsManager)
                }
                .zIndex(0)

                ToolBar(
                    window: $window,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .zIndex(1000)

                overlays
            }
            
            .padding(.top)
            .padding(.horizontal)
            .background(TertiaryColor.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.1), value: dayCode)
            .onAppear {
                loadData()
                resetHomeScroll = true
                if lastSeenVersion != version || isFirstLaunch { whatsNewPopup = true }
                if isFirstLaunch { UserDefaults.standard.set(true, forKey: "HasLaunchedBefore") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.saveDataForWidget() }
                updateNightlyNotification()
            }
            .onChange(of: eventsManager.events) { _, _ in
                render()
                saveScheduleLinesWithEvents()
                saveEventsToCloud()
                saveDataForWidget()
            }
            .onChange(of: dayCode) { oldDay, newDay in
                guard oldDay != newDay else { return }
                resetHomeScroll = true
                saveEventsToCloud()
                updateLiveActivity()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    saveDataForWidget()
                    updateNightlyNotification()
                    updateLiveActivity()
                case .background:
                    saveDataForWidget()
                    updateNightlyNotification()
                default:
                    break
                }
            }
            .onChange(of: window) { oldWindow, newWindow in
                guard oldWindow != newWindow else { return }
                withAnimation(.snappy) { showCalendarGrid = false }
                saveClassesToCloud()
                saveEventsToCloud()
                resetHomeScroll = true
            }
            .onChange(of: onboardingClasses) { _, newClasses in
                guard !newClasses.isEmpty else { return }
                applyOnboardingClassesIfNeeded()
                saveClassesToCloud()
            }
            .onChange(of: PrimaryColor)  { _, _ in saveTheme() }
            .onChange(of: SecondaryColor){ _, _ in saveTheme() }
            .onChange(of: TertiaryColor) { _, _ in saveTheme() }
            .onChange(of: NotificationSettings.isEnabled) { _, _ in updateNightlyNotification() }
            .onChange(of: NotificationSettings.time)      { _, _ in updateNightlyNotification() }
            .onReceive(ticker) { _ in
                render()
                saveScheduleLinesWithEvents()
                saveDataForWidget()
                setIsPortrait()
                updateLiveActivity()

                let now = Date()
                let lastWidgetCheck = SharedGroup.defaults.object(forKey: "LastWidgetCheck") as? Date ?? Date.distantPast
                if now.timeIntervalSince(lastWidgetCheck) > 30 {
                    SharedGroup.defaults.set(now, forKey: "LastWidgetCheck")
                    handleWidgetRefreshRequest()
                }
            }
        }
    }

    // MARK: - Top Header

    @ViewBuilder
    private var topHeader: some View {
        Text("Version - \(version)\nBugs / Ideas - Email acroyset@gmail.com")
            .font(.system(size: iPad ? 12 : 10, weight: .regular))
            .foregroundStyle(TertiaryColor.highContrastTextColor())
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

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        if tutorial != TutorialState.Hidden {
            TutorialView(
                tutorial: $tutorial,
                PrimaryColor: PrimaryColor,
                TertiaryColor: TertiaryColor,
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
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                isFirstLaunch: isFirstLaunch,
                whatsNew: whatsNew
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .zIndex(3000)
        }

        if scheduleRetryAttempt > 0 {
            VStack(spacing: 8) {
                SpinningGear(color: PrimaryColor)
                Text("Loading...")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(PrimaryColor.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = scheduleLoadError {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 32))
                    .foregroundStyle(PrimaryColor.opacity(0.6))
                Text(error)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(PrimaryColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentView: some View {
        switch window {
        case .Home:
            HomeView(
                selectedDate: $selectedDate,
                showCalendarGrid: $showCalendarGrid,
                scrollTarget: $scrollTarget,
                addEvent: $addEvent,
                dayCode: dayCode,
                note: note,
                scheduleLines: scheduleLines,
                scheduleDict: scheduleDict,
                data: data,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                isPortrait: isPortrait,
                resetHomeScroll: $resetHomeScroll,
                onDatePick: applySelectedDate(_:))
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
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )

        case .ClassesView:
            ClassesView(
                data: Binding(
                    get: { data ?? ScheduleData(classes: [], days: []) },
                    set: { newValue in
                        data = newValue
                        saveClassesToCloud()
                    }
                ),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                isPortrait: isPortrait
            )

        case .Profile:
            ProfileMenu(
                data: $data,
                tutorial: $tutorial,
                PrimaryColor: $PrimaryColor,
                SecondaryColor: $SecondaryColor,
                TertiaryColor: $TertiaryColor,
                iPad: iPad,
                isPortrait: isPortrait
            )
        }
    }

    // MARK: - Firebase / Cloud

    private func loadData() {
        guard data == nil else { return }
        loadLocalData()
        loadFromCloud()
        eventsManager.setAuthManager(authManager)
        loadEventsFromCloud()
        if !hasTriedFetchingSchedule {
            hasTriedFetchingSchedule = true
            fetchScheduleFromGoogleSheets()
        }
    }

    private func saveThemeLocally(_ theme: ThemeColors) {
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetManager.shared.saveTheme(theme)
        }
    }

    private func loadThemeLocally() {
        guard let data = UserDefaults.standard.data(forKey: "LocalTheme"),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else { return }
        PrimaryColor = Color(hex: theme.primary)
        SecondaryColor = Color(hex: theme.secondary)
        TertiaryColor = Color(hex: theme.tertiary)
    }

    private func saveTheme() {
        let theme = ThemeColors(
            primary: PrimaryColor.toHex() ?? "#00A5FFFF",
            secondary: SecondaryColor.toHex() ?? "#00A5FF19",
            tertiary: TertiaryColor.toHex() ?? "#FFFFFFFF"
        )
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            WidgetManager.shared.saveTheme(theme)
        }
        if authManager.user != nil { debouncedCloudSave(theme: theme) }
    }

    private func debouncedCloudSave(theme: ThemeColors) {
        themeDebounceTask?.cancel()
        if let lastTheme = lastSavedTheme,
           lastTheme.primary == theme.primary,
           lastTheme.secondary == theme.secondary,
           lastTheme.tertiary == theme.tertiary { return }
        themeDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    saveClassesToCloud()
                    await MainActor.run { lastSavedTheme = theme }
                }
            } catch {}
        }
    }

    private func loadLocalData() {
        let classes: [ClassItem] = {
            do {
                let url = try ensureWritableClassesFile()
                let contents = try String(contentsOf: url, encoding: .utf8)
                return contents.split(whereSeparator: \.isNewline).map { parseClass(String($0)) }
            } catch {
                print("❌ Failed to load Classes from Documents:", error)
                return []
            }
        }()

        guard let daysURL = Bundle.main.url(forResource: "Days", withExtension: "txt") else {
            output = "Days.txt not found in bundle."; return
        }
        let daysContents = (try? String(contentsOf: daysURL, encoding: .utf8)) ?? ""
        let days = parseDays(daysContents)
        data = ScheduleData(classes: classes, days: days)
        applyOnboardingClassesIfNeeded()

        if !hasTriedFetchingSchedule {
            hasTriedFetchingSchedule = true
            fetchScheduleFromGoogleSheets()
        }
    }

    private func loadFromCloud() {
        guard let user = authManager.user, !hasLoadedFromCloud else { return }
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
                    self.PrimaryColor = Color(hex: theme.primary)
                    self.SecondaryColor = Color(hex: theme.secondary)
                    self.TertiaryColor = Color(hex: theme.tertiary)
                    self.saveThemeLocally(theme)
                    self.saveDataForWidget()
                    self.hasLoadedFromCloud = true
                }
            } catch {
                print("❌ Failed to load from cloud: \(error)")
            }
        }
    }

    private func saveClassesToCloud() {
        guard let user = authManager.user, let data = data else { return }
        Task {
            do {
                let theme = ThemeColors(
                    primary: PrimaryColor.toHex() ?? "#00A5FFFF",
                    secondary: SecondaryColor.toHex() ?? "#00A5FF19",
                    tertiary: TertiaryColor.toHex() ?? "#FFFFFFFF"
                )
                try await dataManager.saveToCloud(
                    classes: data.classes,
                    theme: theme,
                    isSecondLunch: data.isSecondLunch,
                    for: user.id
                )
                DispatchQueue.main.async { overwriteClassesFile(with: data.classes) }
            } catch {
                print("❌ Failed to save classes to cloud: \(error)")
            }
        }
    }

    // MARK: - Helpers

    func getDayInfo(for currentDay: String) -> Day? {
        let di = getDayNumber(for: currentDay) ?? 0
        return data?.days[di]
    }

    func getTomorrowsDayCode() -> String {
        guard let scheduleDict = scheduleDict else { return "Unknown" }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd-yy"
        return scheduleDict[formatter.string(from: tomorrow)]?[0] ?? "Unknown"
    }

    private func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[currentDay.lowercased()],
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return di
    }

    private func applySelectedDate(_ date: Date) {
        selectedDate = date
        let key = getKeyToday()
        if let day = scheduleDict?[key] {
            dayCode = day[0]
            note = day[1]
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            render()
            DispatchQueue.main.async { self.scrollTarget = ScheduleRenderer.shared.currentClassIndex(in: self.scheduleLines) ?? 0 }
            output = ""
        } else {
            output = "No schedule found for \(key)"
            dayCode = "None"
            SharedGroup.defaults.set("", forKey: "CurrentDayCode")
        }
    }

    private func getKeyToday() -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.timeZone = .current
        f.dateFormat = "MM-dd-yy"
        return f.string(from: selectedDate)
    }

    private func parseClass(_ line: String) -> ClassItem {
        let parts = line.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 4 { return ClassItem(name: parts[3], teacher: parts[1], room: parts[2]) }
        if parts.count == 3 { return ClassItem(name: parts[0], teacher: parts[1], room: parts[2]) }
        return ClassItem(name: "None", teacher: "None", room: "None")
    }

    private func parseDays(_ contents: String) -> [Day] {
        var days: [Day] = []; var cur = Day()
        for raw in contents.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "$end" { days.append(cur); cur = Day(); continue }
            let parts = line.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 3 {
                cur.names.append(parts[0])
                cur.startTimes.append(Time(parts[1]))
                cur.endTimes.append(Time(parts[2]))
            } else { cur.name = parts[0] }
        }
        return days
    }

    private func parseCSV(_ csvString: String) {
        guard let tempDict = CSVParser.parseScheduleCSV(csvString) else {
            DispatchQueue.main.async { self.output = "Failed to load schedule." }
            return
        }
        DispatchQueue.main.async {
            self.scheduleDict = tempDict
            self.applySelectedDate(self.selectedDate)
            if let dictData = try? JSONEncoder().encode(tempDict) {
                SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
            }
            self.updateNightlyNotification()
            self.saveDataForWidget()
        }
    }
    
    private func render() {
        scheduleLines = ScheduleRenderer.shared.render(
            dayCode: dayCode,
            selectedDate: selectedDate,
            data: data ?? ScheduleData(classes: [], days: []),
            events: eventsManager.events
        )
    }

    private func setIsPortrait() {
        let width = UIScreen.main.bounds.width
        let height = UIScreen.main.bounds.height
        isPortrait = height > width
    }

    private func refreshAllData() async {
        await fetchScheduleFromGoogleSheetsAsync()
        if let user = authManager.user {
            do {
                let (cloudClasses, theme, _) = try await dataManager.loadFromCloud(for: user.id)
                DispatchQueue.main.async {
                    if !cloudClasses.isEmpty, var currentData = self.data {
                        currentData.classes = cloudClasses
                        self.data = currentData
                        overwriteClassesFile(with: cloudClasses)
                    }
                    self.PrimaryColor = Color(hex: theme.primary)
                    self.SecondaryColor = Color(hex: theme.secondary)
                    self.TertiaryColor = Color(hex: theme.tertiary)
                    SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
                    self.render()
                    self.saveScheduleLinesWithEvents()
                    self.saveTheme()
                }
            } catch { print("❌ Failed to refresh from cloud: \(error)") }
        }
    }

    private func fetchScheduleFromGoogleSheets() {
        Task { await fetchWithRetry(attempt: 1) }
    }

    private func fetchWithRetry(attempt: Int, maxAttempts: Int = 10) async {
        let csvURL = "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/export?format=csv&gid=0"
        guard let url = URL(string: csvURL) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let csv = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            DispatchQueue.main.async {
                self.scheduleRetryAttempt = 0
                self.scheduleLoadError = nil
                self.parseCSV(csv)
                self.applySelectedDate(self.selectedDate)
                self.saveDataForWidget()
            }
        } catch {
            if attempt < maxAttempts {
                DispatchQueue.main.async {
                    self.scheduleRetryAttempt = attempt
                }
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                await fetchWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts)
            } else {
                DispatchQueue.main.async {
                    self.scheduleRetryAttempt = 0
                    self.scheduleLoadError = "Could not load schedule. Close and reopen the app to try again."
                }
            }
        }
    }

    private func fetchScheduleFromGoogleSheetsAsync() async {
        await fetchWithRetry(attempt: 1)
    }

    private func saveEventsToCloud() { eventsManager.saveToCloud(using: authManager) }
    private func loadEventsFromCloud() { eventsManager.loadFromCloud(using: authManager) }

    func updateNightlyNotification() {
        if let scheduleDict = scheduleDict {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            let key = formatter.string(from: tomorrow)
            let rawCode = (scheduleDict[key] ?? ["",""])[0]
            NotificationManager.shared.scheduleNightly(dayCode: rawCode)
        } else {
            NotificationManager.shared.scheduleNightly(dayCode: "")
        }
    }
    
    private func applyOnboardingClassesIfNeeded() {
        guard !onboardingClasses.isEmpty else { return }
        guard var currentData = data else { return }
        for (i, item) in onboardingClasses.enumerated() {
            guard i < currentData.classes.count else { break }
            // Only overwrite fields the user actually filled in
            let name = item.name.trimmingCharacters(in: .whitespaces)
            let teacher = item.teacher.trimmingCharacters(in: .whitespaces)
            let room = item.room.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty    { currentData.classes[i].name    = name }
            if !teacher.isEmpty { currentData.classes[i].teacher = teacher }
            if !room.isEmpty    { currentData.classes[i].room    = room }
        }

        data = currentData
        overwriteClassesFile(with: currentData.classes)
        saveDataForWidget()
    }
    
    private func saveDataForWidget() {
        WidgetManager.shared.saveData(
            scheduleDict: scheduleDict,
            data: data,
            dayCode: dayCode
        )
    }

    private func saveScheduleLinesWithEvents() {
        WidgetManager.shared.saveScheduleLinesWithEvents(
            scheduleLines: scheduleLines,
            events: eventsManager.events,
            dayCode: dayCode,
            selectedDate: selectedDate
        )
    }

    private func handleWidgetRefreshRequest() {
        WidgetManager.shared.handleRefreshRequestIfNeeded {
            await self.refreshAllData()
        }
    }

    private func updateLiveActivity() {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let dayName = getDayInfo(for: dayCode)?.name ?? dayCode
        WidgetManager.shared.updateLiveActivity(
            scheduleLines: scheduleLines,
            dayCode: dayCode,
            dayName: dayName,
            isToday: isToday
        )
    }
    
    private struct SpinningGear: View {
        let color: Color
        @State private var rotation: Double = 0

        var body: some View {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 32))
                .foregroundStyle(color.opacity(0.6))
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360
                    }
                }
        }
    }
}
