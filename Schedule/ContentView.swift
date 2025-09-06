//
//  ContentView.swift (Updated with Firebase)
//  Schedule
//

import SwiftUI
import Foundation
import WidgetKit

var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var int: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&int)

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 8: // RRGGBBAA
            r = Double((int & 0xFF000000) >> 24) / 255
            g = Double((int & 0x00FF0000) >> 16) / 255
            b = Double((int & 0x0000FF00) >> 8) / 255
            a = Double(int & 0x000000FF) / 255
        case 6: // RRGGBB
            r = Double((int & 0xFF0000) >> 16) / 255
            g = Double((int & 0x00FF00) >> 8) / 255
            b = Double(int & 0x0000FF) / 255
            a = 1.0
        default:
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

extension Color {
    /// Convert a SwiftUI Color into a hex string like "#RRGGBBAA"
    func toHex(includeAlpha: Bool = true) -> String? {
        let uiColor = UIColor(self)
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }
        
        if includeAlpha {
            let rgba: Int = (Int)(r * 255)<<24 | (Int)(g * 255)<<16 | (Int)(b * 255)<<8 | (Int)(a * 255)
            return String(format:"#%08x", rgba)
        } else {
            let rgb: Int = (Int)(r * 255)<<16 | (Int)(g * 255)<<8 | (Int)(b * 255)
            return String(format:"#%06x", rgb)
        }
    }
}

private struct ToolBar: View {
    @Binding var window: Window
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    let tools = ["Home", "News", "Clubs", "Edit Classes", "Settings", "Profile"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                    ToolButton(
                        window: $window,
                        index: index,
                        tool: tool,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                }
            }
            .padding(.horizontal) // optional: adds padding on left/right
        }
    }
}

struct ToolButton: View {
    @Binding var window: Window
    var index: Int
    var tool: String
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        Button {
            if let w = Window(rawValue: index) {
                window = w
            }
        } label: {
            Text(tool)
                .font(.system(
                    size: iPad ? 32 : 16,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundColor(window.rawValue == index ? TertiaryColor : PrimaryColor)
                .multilineTextAlignment(.trailing)
                .padding(12)
                .background(window.rawValue == index ? PrimaryColor : SecondaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// Updated ContentView with Firebase integration
struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    
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
    
    @State private var window: Window = Window.Home
    
    @State private var PrimaryColor: Color = .blue
    @State private var SecondaryColor: Color = .blue.opacity(0.1)
    @State private var TertiaryColor: Color = .primary
    
    @State private var isPortrait: Bool = !iPad
    @State private var hasLoadedFromCloud = false
    @State private var tutorial = TutorialState.Hidden
    
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var title: String {
        switch tutorial {
        case .Hidden:      return "Error"
        case .Intro:       return "Welcome to Schedule!"
        case .DateNavigator: return "Date Navigator"
        case .News:        return "News"
        case .ClassEditor: return "Class Editor"
        case .Settings:    return "Settings"
        case .Profile:     return "Profile"
        case .Outro:       return "Thanks!"
        }
    }
    var info: String {
        switch tutorial {
        case .Hidden:      return "Error"
        case .Intro:       return "This is a schedule app for Saint Francis High School. It allows you to view your schedule, add new classes, and edit your existing ones!"
        case .DateNavigator: return "Access the date navigator by clicking on the date in the home screen.\n\nThis is how you can choose your dates for the whole year!"
        case .News:        return "Access the news tab by clicking on the news icon in the toolbar.\n\nThis is where you can see current events like clubs football games and everything inbetween!"
        case .ClassEditor: return "Access the class editor by clicking on the edit class icon in the toolbar.\n\nThis is how you can edit your classes."
        case .Settings:    return "Access the settings tab by clicking on the settings icon in the toolbar.\n\nThis is where you can change preferances like the color scheme!"
        case .Profile:     return "Access the profile tab by clicking on the profile icon in the toolbar.\n\nThis is how you can sign out or sync your devices."
        case .Outro:       return "Thanks for downloading Saint Francis Schedule!"
        }
    }
    
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
                
                Text("Version - Beta 1.6\nBugs / Ideas - Email acroyset@gmail.com")
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
                
                switch window {
                case .Home:
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
                        
                        ClassItemScroll(
                            scheduleLines: scheduleLines,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            note: note,
                            dayCode: dayCode,
                            output: output,
                            scrollTarget: $scrollTarget
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
                    let bindingData = Binding<ScheduleData>(
                        get: { self.data ?? ScheduleData(classes: [], days: []) },
                        set: {
                            self.data = $0
                            saveClassesToCloud()
                        }
                    )
                    
                    ClassEditor(
                        data: bindingData,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        isPortrait: isPortrait
                    )
                    
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
                VStack{
                    Text(title)
                        .font(.system(
                            size: iPad ? 40 : 30,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                    
                    Divider()
                    
                    Text(info)
                        .font(.system(
                            size: iPad ? 24 : 15,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                        .frame(alignment: .leading)
                    
                    HStack {
                        Text("For more help visit our ")
                            .font(.footnote)
                            .foregroundStyle(TertiaryColor.highContrastTextColor())
                        Text("support website")
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .underline()
                            .onTapGesture {
                                if let url = URL(string: "https://sites.google.com/view/sf-schedule-help/home") {
                                    UIApplication.shared.open(url)
                                }
                            }
                    }
                    
                    HStack {
                        Button {
                            // Swipe right - go to previous day
                            if let x = TutorialState(rawValue: tutorial.rawValue-1){
                                tutorial = x
                            }
                        } label: { Image(systemName: "chevron.left") }

                        Spacer()

                        Button {
                            if tutorial == .Outro{
                                tutorial = .Hidden
                            } else if let x = TutorialState(rawValue: tutorial.rawValue+1){
                                tutorial = x
                            }
                        } label: { Image(systemName: "chevron.right") }
                    }
                    .padding(8)
                    .padding(.horizontal)
                }
                .padding(12)
                .frame(maxWidth: iPad ? 500 : 300)
                .background(TertiaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(radius: 20)
            }
            
            
            if whatsNewPopup {
                VStack{
                    Text("Whats New?")
                        .font(.system(
                            size: iPad ? 40 : 30,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                    
                    Divider()
                    
                    Text("\n- Widgit! <----- !!!\n- Tutorial\n- Improved Cloud Saving\n- Bug Fixes")
                        .font(.system(
                            size: iPad ? 24 : 15,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                        .frame(alignment: .leading)
                    
                    Button {
                        tutorial = TutorialState.Intro
                        whatsNewPopup = false
                    } label: {
                        Text("Start Tutorial")
                            .font(.system(
                                size: iPad ? 24 : 15,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .foregroundColor(PrimaryColor)
                            .multilineTextAlignment(.trailing)
                            .padding(12)
                            .background(SecondaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
                .frame(maxWidth: iPad ? 500 : 300)
                .background(TertiaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(radius: 20)
            }
        }
        .padding()
        .background(TertiaryColor.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.1), value: dayCode)
        .onAppear {
            loadData()
            setScroll()
        }
        .onChange(of: dayCode) { oldDay, newDay in
            guard oldDay != newDay else { return }
            setScroll()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active else { return }
            if (hasLoadedFromCloud) {saveClassesToCloud()}
            //window = Window.Home
            applySelectedDate(Date())
            //setScroll()
        }
        .onChange(of: window) { oldWindow, newWindow in
            guard oldWindow != newWindow else { return }
            withAnimation(.snappy){
                showCalendarGrid = false;
            }
        }
        .onReceive(ticker) { _ in
            saveTheme()
            saveScheduleLines()
            render()
            setIsPortrait()
        }
    }
    
    // MARK: - Firebase Integration Methods
    
    private func loadData() {
        guard data == nil else { return }
        
        // Load local data first (for offline support)
        loadLocalData()
        
        // Then try to load from cloud
        loadFromCloud()
    }
    
    private func loadLocalData() {
        let classes: [ClassItem] = {
            do {
                let url = try ensureWritableClassesFile()
                let contents = try String(contentsOf: url, encoding: .utf8)
                return contents.split(whereSeparator: \.isNewline).map { parseClass(String($0)) }
            } catch {
                print("Failed to load Classes from Documents:", error)
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
                let (cloudClasses, theme) = try await dataManager.loadFromCloud(for: user.id)
                if !cloudClasses.isEmpty {
                    DispatchQueue.main.async {
                        if var currentData = self.data {
                            currentData.classes = cloudClasses
                            self.data = currentData
                        }
                        // Also save to local file as backup
                        overwriteClassesFile(with: cloudClasses)
                    }
                }
                
                PrimaryColor   = Color(hex: theme.primary)
                SecondaryColor = Color(hex: theme.secondary)
                TertiaryColor  = Color(hex: theme.tertiary)
                
                hasLoadedFromCloud = true
            } catch {
                print("Failed to load classes from cloud: \(error)")
            }
        }
    }
    
    private func saveClassesToCloud() {
        guard let user = authManager.user,
              let classes = data?.classes else { return }
        
        Task {
            do {
                let theme = ThemeColors(
                    primary: PrimaryColor.toHex() ?? "#0000FF",
                    secondary: SecondaryColor.toHex() ?? "#0000FF10",
                    tertiary: TertiaryColor.toHex() ?? "#FFFFFF"
                )
                try await dataManager.saveToCloud(classes: classes, theme:theme,  for: user.id)
                // Also save locally as backup
                DispatchQueue.main.async {
                    overwriteClassesFile(with: classes)
                }
            } catch {
                print("Failed to save classes to cloud: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods (same as before)
    
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
    
    private func render() {
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
        
        if (isToday){
            scheduleLines.append(ScheduleLine(content: "Current Time: \(now.string(showSeconds: true))"))
        }
        
        for i in d.names.indices {
            let nameRaw = d.names[i]
            let start   = d.startTimes[i]
            let end     = d.endTimes[i]
            let isCurrentClass = (start <= now && now < end) && isToday
            
            if (isToday){
                if i == 0 && now < start {
                    scheduleLines.append(ScheduleLine(
                        content: "",
                        isCurrentClass: true,
                        timeRange: "Now to \(start.string())",
                        className: "Before School"))
                }
                
                if i != 0 && d.endTimes[i-1] <= now && now < start {
                    let endT = start
                    let startT = d.endTimes[i-1]
                    let p = progressValue(start: startT.seconds, end: endT.seconds, now: nowSec)
                    if (
                        startT > Time(h:8, m:0, s:0) &&
                        endT < Time(h:14, m:30, s:0) &&
                        endT.seconds - startT.seconds <= 600
                    ){
                        scheduleLines.append(ScheduleLine(
                            content: "",
                            isCurrentClass: true,
                            timeRange: "\(startT.string()) to \(endT.string())",
                            className: "Passing Period",
                            startSec: startT.seconds,
                            endSec: endT.seconds,
                            progress: p
                        ))
                    } else {
                        scheduleLines.append(ScheduleLine(
                            content: "",
                            isCurrentClass: true,
                            timeRange: "\(startT.string()) to \(endT.string())",
                            className: "Free Time",
                            startSec: startT.seconds,
                            endSec: endT.seconds,
                            progress: p
                        ))
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
                
                scheduleLines.append(ScheduleLine(
                    content: "",
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: c.name,
                    teacher: teacher,
                    room: room,
                    startSec: start.seconds,
                    endSec: end.seconds,
                    progress: p
                ))
            } else {
                scheduleLines.append(ScheduleLine(
                    content: "",
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw))
            }
            
            if (isToday){
                if i == d.names.count - 1 && end < now {
                    scheduleLines.append(ScheduleLine(
                        content: "",
                        isCurrentClass: true,
                        timeRange: "\(end.string()) to Now",
                        className: "After School"))
                }
            }
        }
    }
    
    // MARK: - Parsing / Utils (same as before)
    
    private func applySelectedDate(_ date: Date) {
        selectedDate = date
        let key = getKeyToday()
        
        if let day = scheduleDict?[key] {
            dayCode = day[0]
            note = day[1]
            render()
            DispatchQueue.main.async {
                scrollTarget = currentClassIndex() ?? 0
            }
            output = ""
        } else {
            output = "No schedule found for \(key)"
            dayCode = "None"
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
            let nameShort = parts[0]
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
        }
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
        }.resume()
    }
    
    private func progressValue(start: Int, end: Int, now: Int) -> Double {
        guard end > start else { return 0 }
        if now <= start { return 0 }
        if now >= end { return 1 }
        return Double(now - start) / Double(end - start)
    }
    
    private func setScroll() -> Void {
        render()
        DispatchQueue.main.async {
            scrollTarget = currentClassIndex() ?? 0
        }
    }
    
    private func setIsPortrait() -> Void {
        let width = UIScreen.main.bounds.width
        let height = UIScreen.main.bounds.height
        isPortrait = height > width
    }
    
    private func saveScheduleLines() {
        do {
            let data = try JSONEncoder().encode(scheduleLines)
            SharedGroup.defaults.set(data, forKey: SharedGroup.key)
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        } catch {
            print("Encoding failed:", error)
        }
    }
    
    private func saveTheme() {
        // convert to hex or named string
        let theme = ThemeColors(
            primary: PrimaryColor.toHex() ?? "#0000FF",
            secondary: SecondaryColor.toHex() ?? "#0000FF10",
            tertiary: TertiaryColor.toHex() ?? "#FFFFFF"
        )
        if let data = try? JSONEncoder().encode(theme) {
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
    }
}

func copyText(from sourcePath: String, to destinationPath: String) {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    let destinationURL = URL(fileURLWithPath: destinationPath)
    
    do {
        // 1. Read text from source file
        let text = try String(contentsOf: sourceURL, encoding: .utf8)
        
        // 2. Write text into destination file
        try text.write(to: destinationURL, atomically: true, encoding: .utf8)
        
        print("✅ Successfully copied text to \(destinationURL.path)")
    } catch {
        print("❌ Error copying text: \(error)")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationManager())
    }
}
