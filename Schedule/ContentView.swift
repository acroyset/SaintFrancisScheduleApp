//
//  ContentView.swift (MINIMAL FIX)
//  Schedule
//
//  Only extract UI components, keep all logic intact
//

import SwiftUI
import Foundation
import WidgetKit

let version = "Beta 1.9"
let whatsNew = "\n- Second Lunch! <----- !!!\n- Bug Fixes with Personal Events"

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    @StateObject private var eventsManager = CustomEventsManager()
    
    @State private var output = "Loading…"
    @State private var dayCode = ""
    @State private var note = ""
    @State private var scheduleDict: [String: [String]]? = nil
    @State private var hasTriedFetchingSchedule = false
    @State private var scheduleLines: [ScheduleLine] = []
    @State private var data: ScheduleData? = nil
    @State private var selectedDate = Date()
    @State private var scrollTarget: Int? = nil
    @State private var showCalendarGrid = false
    @State private var whatsNewPopup = true
    
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
        ZStack {
            Background(
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            .onTapGesture(perform: {
                withAnimation(.snappy){
                    showCalendarGrid = false
                    whatsNewPopup = false
                    tutorial = .Hidden
                }
            })
            
            VStack {
                
                Text("Version - \(version)\nBugs / Ideas - Email acroyset@gmail.com")
                    .font(.footnote)
                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .onTapGesture(perform: {
                    withAnimation(.snappy){
                        showCalendarGrid = false
                        whatsNewPopup = false
                        tutorial = .Hidden
                    }
                })
                
                mainContentView
                    .environmentObject(eventsManager)
                    
                Divider()
                Spacer(minLength: 12)
                
                ToolBar(
                    window: $window,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                    
            }
            
            if tutorial != TutorialState.Hidden {
                TutorialView(
                    tutorial: $tutorial,
                    PrimaryColor: PrimaryColor,
                    TertiaryColor: TertiaryColor
                )
            }
            
            if whatsNewPopup {
                WhatsNewView(
                    whatsNewPopup: $whatsNewPopup,
                    tutorial: $tutorial,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
            }
        }
        .padding()
        .background(TertiaryColor.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.1), value: dayCode)
        .onAppear {
            loadData()
            setScroll()
            
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
                
            case .background:
                saveDataForWidget()
                
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
        .onReceive(ticker) { _ in
            saveTheme()
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
    private var mainContentView: some View {
        switch window {
        case .Home:
            homeView
            
        case .News:
            NewsMenu(
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            
        case .Clubs:
            ClubView(
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            
        case .ClassEditor:
            classEditorView
            
        case .Settings:
            Settings(
                PrimaryColor: $PrimaryColor,
                SecondaryColor: $SecondaryColor,
                TertiaryColor: $TertiaryColor,
                isPortrait: isPortrait
            )
            
        case .Profile:
            ProfileMenu(
                data: $data,
                PrimaryColor: $PrimaryColor,
                SecondaryColor: $SecondaryColor,
                TertiaryColor: $TertiaryColor,
                iPad: iPad
            )
        }
    }
    
    private var homeView: some View {
        VStack {
            dayHeaderView(
                dayInfo: getDayInfo(for: dayCode),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            .onTapGesture(perform: {
                withAnimation(.snappy){
                    showCalendarGrid = false
                    whatsNewPopup = false
                    tutorial = .Hidden
                }
            })
            
            DateNavigator(
                showCalendar: $showCalendarGrid,
                date: $selectedDate,
                onPick: { applySelectedDate($0)},
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                scheduleDict: scheduleDict
            )
            .padding(.horizontal, 12)
            .zIndex(10)
            
            Divider()
            
            let cal = Calendar.current
            let isToday = cal.isDateInToday(selectedDate)
            
            ClassItemScroll(
                scheduleLines: scheduleLines,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                note: note,
                dayCode: dayCode,
                output: output,
                isToday: isToday,
                iPad: iPad,
                scrollTarget: $scrollTarget,
                addEvent: $addEvent,
                currentDate: selectedDate
            )
            .onTapGesture(perform: {
                withAnimation(.snappy){
                    showCalendarGrid = false;
                    whatsNewPopup = false
                    tutorial = .Hidden
                }
            })
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold {
                        withAnimation(.snappy) {
                            let new = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            selectedDate = new
                            applySelectedDate(new)
                        }
                    } else if value.translation.width < -threshold {
                        withAnimation(.snappy) {
                            let new = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                            selectedDate = new
                            applySelectedDate(new)
                        }
                    }
                }
        )
    }
    
    private var classEditorView: some View {
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
            primary: PrimaryColor.toHex() ?? "#0000FF",
            secondary: SecondaryColor.toHex() ?? "#0000FF10",
            tertiary: TertiaryColor.toHex() ?? "#FFFFFF"
        )
        
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
        
        if authManager.user != nil {
            saveClassesToCloud()
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
                    primary: PrimaryColor.toHex() ?? "#0000FF",
                    secondary: SecondaryColor.toHex() ?? "#0000FF10",
                    tertiary: TertiaryColor.toHex() ?? "#FFFFFF"
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
    
    private func getDayInfo(for currentDay: String) -> Day? {
        let di = getDayNumber(for: currentDay) ?? 0
        return data?.days[di]
    }
    
    private func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[currentDay.lowercased()],
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return di
    }
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let daysWithLunchPeriodG = [0, 2, 4, 5, 8, 9]
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
            let isCurrentClass = (start <= now && now < end) && isToday
            
            if (isToday){
                if i != 0 && d.endTimes[i-1] <= now && now < start {
                    let endT = start
                    let startT = d.endTimes[i-1]
                    let p = progressValue(start: startT.seconds, end: endT.seconds, now: nowSec)
                    if (
                        startT > Time(h:8, m:0, s:0) &&
                        endT < Time(h:14, m:30, s:0) &&
                        endT.seconds - startT.seconds <= 600
                    ){
                        tempLines.append((i, ScheduleLine(
                            content: "",
                            base: "",
                            isCurrentClass: true,
                            timeRange: "\(startT.string()) to \(endT.string())",
                            className: "Passing Period",
                            startSec: startT.seconds,
                            endSec: endT.seconds,
                            progress: p
                        )))
                    }
                }
            }
            
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room    = (c.room    == "N" || c.room.isEmpty)    ? "" : c.room
                
                let p = progressValue(start: start.seconds, end: end.seconds, now: nowSec)
                
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: c.name,
                    teacher: teacher,
                    room: room,
                    startSec: start.seconds,
                    endSec: end.seconds,
                    progress: p
                )))
            } else {
                tempLines.append((i, ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: isCurrentClass,
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

                if item.line.base.contains("$4") || item.line.base.contains("$5") {
                    var line = item.line
                    line.startSec = Time(h:11, m:00, s:0).seconds
                    line.endSec   = Time(h:12, m:20, s:0).seconds
                    line.timeRange = "11:00 to 12:20"
                    tempLines[i].line = line
                }
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationManager())
    }
}
