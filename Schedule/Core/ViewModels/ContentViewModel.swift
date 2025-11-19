//
//  ContentViewModel.swift (FIXED)
//  Schedule
//
//  Extracted from ContentView.swift
//

import SwiftUI
import Foundation
import WidgetKit

@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var output = "Loading…"
    @Published var dayCode = ""
    @Published var note = ""
    @Published var scheduleDict: [String: [String]]? = nil
    @Published var hasTriedFetchingSchedule = false
    @Published var scheduleLines: [ScheduleLine] = []
    @Published var data: ScheduleData? = nil
    @Published var selectedDate = Date()
    @Published var scrollTarget: Int? = nil
    @Published var showCalendarGrid = false
    @Published var whatsNewPopup = true
    @Published var addEvent = false
    @Published var window: Window = Window.Home
    @Published var hasLoadedFromCloud = false
    @Published var tutorial = TutorialState.Hidden
    
    // Theme Colors
    @Published var PrimaryColor: Color = .blue
    @Published var SecondaryColor: Color = .blue.opacity(0.1)
    @Published var TertiaryColor: Color = .primary
    
    // MARK: - Dependencies
    private let dataManager = DataManager()
    let eventsManager = CustomEventsManager()
    
    // MARK: - Initialization
    init() {}
    
    // MARK: - Data Loading
    func loadData(authManager: AuthenticationManager) {
        guard data == nil else { return }
        loadLocalData()
        loadFromCloud(authManager: authManager)
        loadEventsFromCloud(authManager: authManager)
        
        if !hasTriedFetchingSchedule {
            hasTriedFetchingSchedule = true
            fetchScheduleFromGoogleSheets()
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
            output = "Days.txt not found in bundle."
            return
        }
        let daysContents = (try? String(contentsOf: daysURL, encoding: .utf8)) ?? ""
        let days = parseDays(daysContents)
        
        data = ScheduleData(classes: classes, days: days)
    }
    
    private func loadFromCloud(authManager: AuthenticationManager) {
        guard let user = authManager.user, !hasLoadedFromCloud else { return }
        
        Task {
            do {
                let (cloudClasses, theme, isSecondLunch) = try await dataManager.loadFromCloud(for: user.id)
                
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
            } catch {
                print("❌ Failed to load from cloud: \(error)")
            }
        }
    }
    
    // MARK: - Date Navigation (KEPT HERE - Don't move!)
    func applySelectedDate(_ date: Date) {
        selectedDate = date
        let key = getKeyToday()
        
        if let day = scheduleDict?[key] {
            dayCode = day[0]
            note = day[1]
            
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            renderWithEvents()
            
            DispatchQueue.main.async {
                self.scrollTarget = self.currentClassIndex() ?? 0
            }
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
    
    private func currentClassIndex() -> Int? {
        if let i = scheduleLines.firstIndex(where: { $0.isCurrentClass && !$0.timeRange.isEmpty }) {
            return i
        }
        return scheduleLines.firstIndex(where: { $0.isCurrentClass }) ??
               scheduleLines.firstIndex(where: { !$0.timeRange.isEmpty })
    }
    
    // MARK: - Schedule Rendering (KEPT HERE - Don't move!)
    func renderWithEvents() {
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
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: [Bool]) -> Bool {
        let daysWithLunchPeriodG = [0, 2, 4, 5, 8, 9]
        let daysWithLunchPeriodB = [1, 3]
        return (isSecondLunch[0] && daysWithLunchPeriodG.contains(dayIndex)) || (isSecondLunch[1] && daysWithLunchPeriodB.contains(dayIndex))
    }
    
    private func checkForEventConflicts(events: [CustomEvent]) {
        for event in events {
            let conflicts = eventsManager.detectConflicts(for: event, with: scheduleLines)
            if !conflicts.isEmpty {
                // Handle conflicts if needed
            }
        }
    }
    
    func saveScheduleLinesWithEvents() {
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
    
    // MARK: - Theme Management
    func saveTheme(authManager: AuthenticationManager) {
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
            saveClassesToCloud(authManager: authManager)
        }
    }
    
    private func saveThemeLocally(_ theme: ThemeColors) {
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
    }
    
    // MARK: - Cloud Sync
    func saveClassesToCloud(authManager: AuthenticationManager) {
        guard let user = authManager.user, let data = data else { return }
        
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
    
    func saveEventsToCloud(authManager: AuthenticationManager) {
        eventsManager.saveToCloud(using: authManager)
    }
    
    func loadEventsFromCloud(authManager: AuthenticationManager) {
        eventsManager.loadFromCloud(using: authManager)
    }
    
    // MARK: - Widget Data
    func saveDataForWidget() {
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
    
    // MARK: - Parsing Helpers
    private func parseClass(_ line: String) -> ClassItem {
        let parts = line.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 4 {
            return ClassItem(name: parts[3], teacher: parts[1], room: parts[2])
        } else if parts.count == 3 {
            return ClassItem(name: parts[0], teacher: parts[1], room: parts[2])
        }
        return ClassItem(name: "None", teacher: "None", room: "None")
    }
    
    private func parseDays(_ contents: String) -> [Day] {
        var days: [Day] = []
        var cur = Day()
        for raw in contents.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "$end" {
                days.append(cur)
                cur = Day()
                continue
            }
            let parts = line.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 3 {
                cur.names.append(parts[0])
                cur.startTimes.append(Time(parts[1]))
                cur.endTimes.append(Time(parts[2]))
            } else {
                cur.name = parts[0]
            }
        }
        return days
    }
    
    // MARK: - Schedule Fetching
    func fetchScheduleFromGoogleSheets() {
        let csvURL = "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/export?format=csv&gid=0"
        guard let url = URL(string: csvURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data, let csv = String(data: data, encoding: .utf8) else { return }
            self.parseCSV(csv)
            self.applySelectedDate(self.selectedDate)
            
            DispatchQueue.main.async {
                self.saveDataForWidget()
            }
        }.resume()
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
}
