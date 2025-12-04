//
//  ContentView.swift (MINIMAL FIX)
//  Schedule
//
//  Only extract UI components, keep all logic intact
//

import SwiftUI
import Foundation
import WidgetKit
import UserNotifications

let version = "Beta 1.11"
let whatsNew = "\n- Liquid Glass on iOS 26 <----- !!!\n- Bug Fixes"

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
    @State private var selectedDate = Date()
    @State private var scrollTarget: Int? = nil
    @State private var showCalendarGrid = false
    @State private var whatsNewPopup = false
    @State private var lastSeenVersion: String = UserDefaults.standard.string(forKey: "LastSeenVersion") ?? ""
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
    
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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background(
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            .onTapGesture(perform: {
                withAnimation(.snappy){
                    showCalendarGrid = false
                    
                    UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                }
            })
            
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
            
            if tutorial != TutorialState.Hidden {
                Color.black.opacity(0.0001)
                    .ignoresSafeArea()
                    .zIndex(2500)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            tutorial = .Hidden
                        }
                    }
                
                TutorialView(
                    tutorial: $tutorial,
                    PrimaryColor: PrimaryColor,
                    TertiaryColor: TertiaryColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                    isFirstLaunch: isFirstLaunch
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(3000)
            }
        }
        .padding(.top)
        .padding(.horizontal)
        .background(TertiaryColor.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.1), value: dayCode)
        .onAppear {
            loadData()
            setScroll()
            
            if lastSeenVersion != version {
                whatsNewPopup = true
            }
            
            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.saveDataForWidget()
            }
        }
        .onChange(of: eventsManager.events) { _, _ in
            renderWithEvents()
            saveScheduleLinesWithEvents()
            saveEventsToCloud()
            saveDataForWidget()
        }
        .onChange(of: dayCode) { oldDay, newDay in
            guard oldDay != newDay else { return }
            setScroll()
            saveEventsToCloud()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                saveDataForWidget()
                WidgetCenter.shared.reloadAllTimelines()
                updateNightlyNotification()
                
            case .background:
                saveDataForWidget()
                updateNightlyNotification()
                
            default:
                break
            }
        }
        .onChange(of: window) { oldWindow, newWindow in
            guard oldWindow != newWindow else { return }
            withAnimation(.snappy){
                showCalendarGrid = false;
            }
            saveClassesToCloud()
            saveEventsToCloud()
        }
        .onChange(of: PrimaryColor) { _, _ in
            saveTheme()
        }
        .onChange(of: SecondaryColor) { _, _ in
            saveTheme()
        }
        .onChange(of: TertiaryColor) { _, _ in
            saveTheme()
        }
        .onChange(of: NotificationSettings.isEnabled) { _, _ in
            updateNightlyNotification()
        }
        .onChange(of: NotificationSettings.time) { _, _ in
            updateNightlyNotification()
        }
        .onReceive(ticker) { _ in
            renderWithEvents()
            saveScheduleLinesWithEvents()
            saveDataForWidget()
            setIsPortrait()
            
            let now = Date()
            let lastWidgetCheck = SharedGroup.defaults.object(forKey: "LastWidgetCheck") as? Date ?? Date.distantPast
            
            if now.timeIntervalSince(lastWidgetCheck) > 30 {
                SharedGroup.defaults.set(now, forKey: "LastWidgetCheck")
                handleWidgetRefreshRequest()
            }
        }
    }
    
    // MARK: - Main Content View
    
    @ViewBuilder
    private var topHeader: some View{
        Text("Version - \(version)\nBugs / Ideas - Email acroyset@gmail.com")
            .font(.system(
                size: iPad ? 12 : 10,
                weight: .regular))
            .foregroundStyle(TertiaryColor.highContrastTextColor())
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .onTapGesture(perform: {
            withAnimation(.snappy){
                showCalendarGrid = false
                
                UserDefaults.standard.set(version, forKey: "LastSeenVersion")
            }
        })


    }
    
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
                onDatePick: applySelectedDate(_:))
            .onTapGesture(perform: {
                withAnimation(.snappy){
                    showCalendarGrid = false
                    whatsNewPopup = false
                    tutorial = .Hidden
                    
                    UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                }
            })
            
        case .News:
            NewsMenu(
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            .padding(.bottom, iPad ? 90 : 80)
            
        case .ClassEditor:
            ClassEditor(
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
            .padding(.bottom, iPad ? 90 : 80)
            
        case .Settings:
            Settings(
                PrimaryColor: $PrimaryColor,
                SecondaryColor: $SecondaryColor,
                TertiaryColor: $TertiaryColor,
                isPortrait: isPortrait
            )
            .padding(.bottom, iPad ? 90 : 80)
            
        case .Profile:
            ProfileMenu(
                data: $data,
                tutorial: $tutorial,
                PrimaryColor: $PrimaryColor,
                SecondaryColor: $SecondaryColor,
                TertiaryColor: $TertiaryColor,
                iPad: iPad
            )
            .padding(.bottom, iPad ? 90 : 80)
        }
    }
    
    // MARK: - Firebase Integration Methods
    
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
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
    }

    private func loadThemeLocally() {
        guard let data = UserDefaults.standard.data(forKey: "LocalTheme"),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else {
            return
        }
        
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
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
        
        if authManager.user != nil {
            debouncedCloudSave(theme: theme)
        }
    }

    private func debouncedCloudSave(theme: ThemeColors) {
        // Cancel any pending save
        themeDebounceTask?.cancel()
        
        // Check if theme actually changed
        if let lastTheme = lastSavedTheme,
           lastTheme.primary == theme.primary,
           lastTheme.secondary == theme.secondary,
           lastTheme.tertiary == theme.tertiary {
            return // No change, don't save
        }
        
        // Schedule a new save after 5 seconds of inactivity
        themeDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                if !Task.isCancelled {
                    saveClassesToCloud()
                    await MainActor.run {
                        lastSavedTheme = theme
                    }
                }
            } catch {
                // Task was cancelled, do nothing
            }
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
        guard let user = authManager.user,
              let data = data else { return }
        
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
                DispatchQueue.main.async {
                    overwriteClassesFile(with: data.classes)
                }
            } catch {
                print("❌ Failed to save classes to cloud: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
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

        let key = formatter.string(from: tomorrow)
        return scheduleDict[key]?[0] ?? "Unknown"
    }

    
    private func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[currentDay.lowercased()],
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return di
    }
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let daysWithLunchPeriodG = [0, 2, 4, 5, 6, 7, 8, 9]
        let daysWithLunchPeriodB = [1, 3]
        return (isSecondLunch[0] && daysWithLunchPeriodG.contains(dayIndex)) || (isSecondLunch[1] && daysWithLunchPeriodB.contains(dayIndex))
    }
    
    private func renderWithEvents() {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(selectedDate)
        
        guard let data = data else { return }
        
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            scheduleLines = []
            if (!dayCode.isEmpty && dayCode != "None") {
                output = "Invalid day code: '\(dayCode)'. Valid codes: G1, B1, G2, B2, A1, A2, A3, A4, L1, L2, S1"
            } else if scheduleDict == nil {
                output = "Loading schedule..."
            }
            return
        }
        
        output = ""
        scheduleLines = []
        let d = data.days[di]
        let now = Time.now()
        let nowSec = now.seconds
        
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: data.isSecondLunch)
        
        var tempLines: [(index: Int, line: ScheduleLine)] = []
        
        for i in d.names.indices {
            let nameRaw = d.names[i]
            let start   = d.startTimes[i]
            let end     = d.endTimes[i]
            
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room    = (c.room    == "N" || c.room.isEmpty)    ? "" : c.room
                
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: false,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: c.name,
                    teacher: teacher,
                    room: room,
                    startSec: start.seconds,
                    endSec: end.seconds,
                    progress: nil
                )))
            } else {
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: false,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw)))
            }
        }
        
        if shouldSwap {
            for (i, item) in tempLines.enumerated() {
                if item.line.className == "Lunch" {
                    var line = item.line
                    line.startSec = Time(h:12, m:25, s:0).seconds
                    line.endSec   = Time(h:13, m:05, s:0).seconds
                    line.timeRange = "12:25 to 1:05"
                    tempLines[i].line = line
                }
                
                // Handle Brunch
                if item.line.className == "Brunch" {
                    var line = item.line
                    line.startSec = Time(h:11, m:10, s:0).seconds
                    line.endSec = Time(h:11, m:35, s:0).seconds
                    line.timeRange = "11:10 to 11:35"
                    tempLines[i].line = line
                }
                
                // Swap Period 4/5 for Lunch days
                if (item.line.base.contains("$4") || item.line.base.contains("$5")) &&
                   tempLines.contains(where: { $0.line.className == "Lunch" }) {
                    var line = item.line
                    line.startSec = Time(h:11, m:00, s:0).seconds
                    line.endSec   = Time(h:12, m:20, s:0).seconds
                    line.timeRange = "11:00 to 12:20"
                    tempLines[i].line = line
                }
                
                // Swap Period 4 for Brunch days
                if item.line.base.contains("$4") &&
                   tempLines.contains(where: { $0.line.className == "Brunch" }) {
                    var line = item.line
                    line.startSec = Time(h:9, m:45, s:0).seconds
                    line.endSec = Time(h:11, m:05, s:0).seconds
                    line.timeRange = "9:45 to 11:05"
                    tempLines[i].line = line
                }
            }
        }
        
        tempLines.sort { first, second in
            guard let firstStart = first.line.startSec, let secondStart = second.line.startSec else {
                return false
            }
            return firstStart < secondStart
        }
        
        for (i, item) in tempLines.enumerated() {
            var line = item.line
            if let startSec = line.startSec, let endSec = line.endSec {
                line.isCurrentClass = (startSec <= nowSec && nowSec < endSec) && isToday
                line.progress = progressValue(start: startSec, end: endSec, now: nowSec)
                tempLines[i].line = line
            }
        }
        
        if isToday {
            var passingSections: [(index: Int, line: ScheduleLine)] = []
            for i in 1..<tempLines.count {
                let prevEnd = tempLines[i-1].line.endSec ?? 0
                let currStart = tempLines[i].line.startSec ?? 0
                
                // Check if there's a gap between classes
                if currStart > prevEnd {
                    let gapDuration = currStart - prevEnd
                    let isCurrentPassing = (prevEnd <= nowSec && nowSec < currStart)
                    
                    // Only show passing period if it's currently active AND gap is 10 minutes or less
                    if isCurrentPassing && gapDuration <= 600 {
                        let p = progressValue(start: prevEnd, end: currStart, now: nowSec)
                        
                        passingSections.append((i, ScheduleLine(
                            content: "",
                            base: "",
                            isCurrentClass: true,
                            timeRange: "\(Time(seconds: prevEnd).string()) to \(Time(seconds: currStart).string())",
                            className: "Passing Period",
                            startSec: prevEnd,
                            endSec: currStart,
                            progress: p
                        )))
                    }
                }
            }
            
            // Insert passing periods in reverse order to maintain indices
            for section in passingSections.reversed() {
                tempLines.insert(section, at: section.index)
            }
        }
        
        scheduleLines = tempLines.map { $0.line }
        
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: selectedDate)
        checkForEventConflicts(events: todaysEvents)
    }

    private func checkForEventConflicts(events: [CustomEvent]) {
        for event in events {
            let conflicts = eventsManager.detectConflicts(for: event, with: scheduleLines)
            
            if !conflicts.isEmpty {
                // Handle conflicts
            }
        }
    }
    
    // MARK: - Parsing / Utils
    
    private func applySelectedDate(_ date: Date) {
        selectedDate = date
        let key = getKeyToday()
        
        if let day = scheduleDict?[key] {
            dayCode = day[0]
            note = day[1]
            
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            
            renderWithEvents()
            DispatchQueue.main.async {
                scrollTarget = currentClassIndex() ?? 0
            }
            output = ""
        } else {
            output = "No schedule found for \(key)"
            dayCode = "None"
            SharedGroup.defaults.set("", forKey: "CurrentDayCode")
        }
    }
    
    private func getKeyToday () -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.timeZone = .current
        f.dateFormat = "MM-dd-yy"
        return f.string(from: selectedDate)
    }
    
    private func currentClassIndex() -> Int? {
        if let i = scheduleLines.firstIndex(where: { $0.isCurrentClass && !$0.timeRange.isEmpty }) { return i }
        return scheduleLines.firstIndex(where: { $0.isCurrentClass }) ??
        scheduleLines.firstIndex(where: { !$0.timeRange.isEmpty })
    }
    
    private func parseClass(_ line: String) -> ClassItem {
        let parts = line.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 4 {
            let nameNormal = parts[3]
            let name = nameNormal
            return ClassItem(
                name: name,
                teacher: parts[1],
                room: parts[2])
        } else if parts.count == 3 {
            return ClassItem(
                name: parts[0],
                teacher: parts[1],
                room: parts[2])
        }
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
            }
            else {
                cur.name = parts[0]
            }
        }
        return days
    }
    
    private func parseCSV(_ csvString: String) {
        var tempDict: [String: [String]] = [:]
        let lines = csvString.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: ",")
            if columns.count >= 3 {
                let date = columns[0].trimmingCharacters(in: .whitespaces)
                let dayType = columns[1].trimmingCharacters(in: .whitespaces)
                let note = columns[2].trimmingCharacters(in: .whitespaces)
                tempDict[date] = [dayType, note]
            }
        }
        DispatchQueue.main.async {
            self.scheduleDict = tempDict
            self.applySelectedDate(self.selectedDate)
            
            if let dictData = try? JSONEncoder().encode(tempDict) {
                SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
            }
            
            updateNightlyNotification()
            
            self.saveDataForWidget()
        }
    }
    
    private func saveDataForWidget() {
        guard let data = data else { return }
        
        if let scheduleDict = scheduleDict,
           let dictData = try? JSONEncoder().encode(scheduleDict) {
            SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
        }
        
        if let classesData = try? JSONEncoder().encode(data.classes) {
            SharedGroup.defaults.set(classesData, forKey: "ScheduleClasses")
        }
        
        if let daysData = try? JSONEncoder().encode(data.days) {
            SharedGroup.defaults.set(daysData, forKey: "ScheduleDays")
        }
        
        SharedGroup.defaults.set(data.isSecondLunch, forKey: "IsSecondLunch")
        SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
        
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
    }
    
    private func getTodaysType() -> [String]? {
        guard let scheduleDict = scheduleDict else { return nil }
        let formatter = DateFormatter(); formatter.dateFormat = "MM-dd-yy"
        return scheduleDict[formatter.string(from: Date())] ?? ["",""]
    }
    
    private func fetchScheduleFromGoogleSheets() {
        let csvURL = "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/export?format=csv&gid=0"
        guard let url = URL(string: csvURL) else { return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data, let csv = String(data: data, encoding: .utf8) else { return }
            self.parseCSV(csv)
            applySelectedDate(selectedDate)
            
            DispatchQueue.main.async {
                self.saveDataForWidget()
            }
        }.resume()
    }
    
    private func setScroll() -> Void {
        renderWithEvents()
        DispatchQueue.main.async {
            scrollTarget = currentClassIndex() ?? 0
        }
    }
    
    private func setIsPortrait() -> Void {
        let width = UIScreen.main.bounds.width
        let height = UIScreen.main.bounds.height
        isPortrait = height > width
    }
    
    private func handleWidgetRefreshRequest() {
        if SharedGroup.defaults.bool(forKey: "WidgetRequestsUpdate") {
            SharedGroup.defaults.set(false, forKey: "WidgetRequestsUpdate")
            
            Task {
                await refreshAllData()
            }
        }
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
                    
                    self.renderWithEvents()
                    self.saveScheduleLinesWithEvents()
                    self.saveTheme()
                }
            } catch {
                print("❌ Failed to refresh from cloud: \(error)")
            }
        }
    }

    private func fetchScheduleFromGoogleSheetsAsync() async {
        let csvURL = "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/export?format=csv&gid=0"
        guard let url = URL(string: csvURL) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let csv = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.parseCSV(csv)
                    self.applySelectedDate(self.selectedDate)
                }
            }
        } catch {
            print("❌ Failed to fetch schedule: \(error)")
        }
    }
    
    private func saveEventsToCloud() {
        eventsManager.saveToCloud(using: authManager)
    }

    private func loadEventsFromCloud() {
        eventsManager.loadFromCloud(using: authManager)
    }
    
    private func saveScheduleLinesWithEvents() {
        var allItems: [ScheduleLine] = scheduleLines
        
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: selectedDate)
        for event in todaysEvents where event.isEnabled {
            let eventLine = ScheduleLine(
                content: "",
                base: "",
                isCurrentClass: false,
                timeRange: "\(event.startTime.string()) to \(event.endTime.string())",
                className: "\(event.title)",
                teacher: event.location,
                room: event.note,
                startSec: event.startTime.seconds,
                endSec: event.endTime.seconds,
                progress: nil
            )
            allItems.append(eventLine)
        }
        
        allItems.sort { first, second in
            guard let firstStart = first.startSec, let secondStart = second.startSec else {
                return false
            }
            return firstStart < secondStart
        }
        
        do {
            let data = try JSONEncoder().encode(allItems)
            SharedGroup.defaults.set(data, forKey: SharedGroup.key)
            SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
            
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            
            let eventsData = try JSONEncoder().encode(eventsManager.events)
            SharedGroup.defaults.set(eventsData, forKey: "CustomEvents")
            
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        } catch {
            print("❌ Encoding failed:", error)
        }
    }
    
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationManager())
    }
}
