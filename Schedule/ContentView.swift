//
//  ContentView.swift (Updated with Firebase)
//  Schedule
//

import SwiftUI
import Foundation
import WidgetKit

var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

func progressValue(start: Int, end: Int, now: Int) -> Double {
    guard end > start else { return 0 }
    if now <= start { return 0 }
    if now >= end { return 1 }
    return Double(now - start) / Double(end - start)
}

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

// Replace the Color extension toHex() method in ContentView.swift

extension Color {
    /// Convert a SwiftUI Color into a hex string like "#RRGGBBAA"
    func toHex(includeAlpha: Bool = true) -> String? {
        // Get UIColor from SwiftUI Color
        guard let components = UIColor(self).cgColor.components else {
            print("⚠️ Failed to get color components")
            return nil
        }
        
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        
        // Handle different color spaces
        switch components.count {
        case 2: // Grayscale
            r = components[0]
            g = components[0]
            b = components[0]
            a = components[1]
        case 4: // RGBA
            r = components[0]
            g = components[1]
            b = components[2]
            a = components[3]
        default:
            print("⚠️ Unexpected color component count: \(components.count)")
            return nil
        }
        
        if includeAlpha {
            let rgba: Int = (Int)(r * 255)<<24 | (Int)(g * 255)<<16 | (Int)(b * 255)<<8 | (Int)(a * 255)
            let hex = String(format:"#%08X", rgba)
            print("🎨 Color to hex: \(hex)")
            return hex
        } else {
            let rgb: Int = (Int)(r * 255)<<16 | (Int)(g * 255)<<8 | (Int)(b * 255)
            let hex = String(format:"#%06X", rgb)
            print("🎨 Color to hex (no alpha): \(hex)")
            return hex
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

struct ConflictNotificationView: View {
    let conflicts: [EventConflict]
    @Binding var isPresented: Bool
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                Text("Schedule Conflicts Detected")
                    .font(.headline)
                    .foregroundColor(PrimaryColor)
                
                Spacer()
                
                Button("Dismiss") {
                    isPresented = false
                }
                .foregroundColor(PrimaryColor)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(conflicts.indices, id: \.self) { index in
                        ConflictRowView(conflict: conflicts[index])
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(TertiaryColor)
        .cornerRadius(12)
        .shadow(radius: 10)
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
    
    @State private var addEvent = false
    
    @State private var window: Window = Window.Home
    
    @State private var PrimaryColor: Color = .blue
    @State private var SecondaryColor: Color = .blue.opacity(0.1)
    @State private var TertiaryColor: Color = .primary
    
    @State private var isPortrait: Bool = !iPad
    @State private var hasLoadedFromCloud = false
    @State private var tutorial = TutorialState.Hidden
    
    @StateObject private var eventsManager = CustomEventsManager()
    
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
        case .ClassEditor: return "Access the class editor by clicking on the edit class icon in the toolbar.\n\nThis is how you can edit your classes. You can also select if you are second lunch or not."
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
                
                Text("Version - Beta 1.8\nBugs / Ideas - Email acroyset@gmail.com")
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
                        
                        let cal = Calendar.current
                        let isToday = cal.isDateInToday(selectedDate)
                        
                        EnhancedClassItemScroll(
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
                    
                    Text("\n- Second Lunch! <----- !!!\n- Personal Events\n- Bug Fixes")
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
            saveEventsToCloud()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // App became active - check for widget requests
                handleWidgetRefreshRequest()
                
                if hasLoadedFromCloud {
                    saveClassesToCloud()
                    saveEventsToCloud() // NEW: Save events to cloud
                }
                
                // Load events from cloud
                loadEventsFromCloud() // NEW: Load events from cloud
                
                applySelectedDate(Date())
                
            case .background:
                // App going to background - save current state
                SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
                saveScheduleLinesWithEvents()
                saveTheme()
                saveEventsToCloud() // NEW: Save events to cloud
                
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
            renderWithEvents() // Use enhanced rendering
            saveScheduleLinesWithEvents() // Use enhanced saving
            setIsPortrait()
            
            // Handle widget refresh requests
            let now = Date()
            let lastWidgetCheck = SharedGroup.defaults.object(forKey: "LastWidgetCheck") as? Date ?? Date.distantPast
            
            if now.timeIntervalSince(lastWidgetCheck) > 30 {
                SharedGroup.defaults.set(now, forKey: "LastWidgetCheck")
                handleWidgetRefreshRequest()
            }
        }
    }
    
    // MARK: - Firebase Integration Methods
    
    private func loadData() {
        guard data == nil else { return }
        
        // Load local data first (for offline support)
        loadLocalData()
        
        // Then try to load from cloud
        loadFromCloud()
        
        loadEventsFromCloud()
    }
    
    private func saveThemeLocally(_ theme: ThemeColors) {
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
    }

    // 4. Add loadThemeLocally helper function
    private func loadThemeLocally() {
        guard let data = UserDefaults.standard.data(forKey: "LocalTheme"),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else {
            return
        }
        
        PrimaryColor = Color(hex: theme.primary)
        SecondaryColor = Color(hex: theme.secondary)
        TertiaryColor = Color(hex: theme.tertiary)
        print("✅ Loaded theme from local storage")
    }

    // 5. Update the existing saveTheme function
    private func saveTheme() {
        let theme = ThemeColors(
            primary: PrimaryColor.toHex() ?? "#0000FF",
            secondary: SecondaryColor.toHex() ?? "#0000FF10",
            tertiary: TertiaryColor.toHex() ?? "#FFFFFF"
        )
        
        // Save locally
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
        
        // Also save to cloud if user is logged in
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

    // In loadFromCloud():
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
                    
                    // Apply theme colors
                    self.PrimaryColor = Color(hex: theme.primary)
                    self.SecondaryColor = Color(hex: theme.secondary)
                    self.TertiaryColor = Color(hex: theme.tertiary)
                    
                    // Also save theme locally
                    self.saveThemeLocally(theme)
                    
                    self.hasLoadedFromCloud = true
                    print("✅ Loaded theme from cloud: \(theme)")
                }
            } catch {
                print("❌ Failed to load from cloud: \(error)")
            }
        }
    }
    
    // In saveClassesToCloud():
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
                print("✅ Saved theme to cloud: \(theme)")
            } catch {
                print("❌ Failed to save classes to cloud: \(error)")
            }
        }
    }

    // Also update refreshAllData() similarly
    
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
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: Bool) -> Bool {
        // Day indices: G1=0, B1=1, G2=2, B2=3, A1=4, A2=5, A3=6, A4=7, L1=8, L2=9, S1=10
        // We only swap on days that have period 4 or 5 with lunch
        // These are: G1, B1, G2, B2, A1, A2
        let daysWithLunchPeriod = [0, 1, 2, 3, 4, 5]
        return isSecondLunch && daysWithLunchPeriod.contains(dayIndex)
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
        
        // Check if we need to swap lunch and period 4/5
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: data.isSecondLunch)
        
        // Build schedule lines with potential swap
        var tempLines: [(index: Int, line: ScheduleLine)] = []
        
        for i in d.names.indices {
            let nameRaw = d.names[i]
            let start   = d.startTimes[i]
            let end     = d.endTimes[i]
            let isCurrentClass = (start <= now && now < end) && isToday
            
            // Add passing periods for today
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
            
            // Add regular classes
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room    = (c.room    == "N" || c.room.isEmpty)    ? "" : c.room
                
                let p = progressValue(start: start.seconds, end: end.seconds, now: nowSec)
                
                tempLines.append((i, ScheduleLine(
                    content: "",
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
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw)))
            }
        }
        
        // Apply SECOND LUNCH override
        if shouldSwap {

            for (i, item) in tempLines.enumerated() {

                if item.line.className == "Lunch" {
                    // 2nd lunch time
                    var line = item.line
                    line.startSec = Time(h:12, m:25, s:0).seconds
                    line.endSec   = Time(h:13, m:05, s:0).seconds
                    line.timeRange = "12:25 to 1:05"
                    tempLines[i].line = line
                }

                if item.line.className.contains("Period 4")
                    || item.line.className.contains("Period 5") {

                    // 4th/5th for 2nd lunch
                    var line = item.line
                    line.startSec = Time(h:11, m:00, s:0).seconds
                    line.endSec   = Time(h:12, m:20, s:0).seconds
                    line.timeRange = "11:00 to 12:20"
                    tempLines[i].line = line
                }
            }
        }

        
        // Extract just the schedule lines in order
        scheduleLines = tempLines.map { $0.line }
        
        // Check for conflicts with custom events
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: selectedDate)
        checkForEventConflicts(events: todaysEvents)
    }

    // Add this new conflict checking function:
    private func checkForEventConflicts(events: [CustomEvent]) {
        for event in events {
            let conflicts = eventsManager.detectConflicts(for: event, with: scheduleLines)
            
            if !conflicts.isEmpty {
                print("Event '\(event.title)' has \(conflicts.count) conflicts")
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
            
            // Save current day code for widget
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
            self.applySelectedDate(self.selectedDate)
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
        // Check if widget requested an update
        if SharedGroup.defaults.bool(forKey: "WidgetRequestsUpdate") {
            SharedGroup.defaults.set(false, forKey: "WidgetRequestsUpdate")
            
            // Refresh data from cloud and Google Sheets
            Task {
                await refreshAllData()
            }
        }
    }

    private func refreshAllData() async {
        // Refresh from Google Sheets
        await fetchScheduleFromGoogleSheetsAsync()
        
        // Refresh from Firebase if user is logged in
        if let user = authManager.user {
            do {
                let (cloudClasses, theme, secondLunch) = try await dataManager.loadFromCloud(for: user.id)
                DispatchQueue.main.async {
                    if !cloudClasses.isEmpty, var currentData = self.data {
                        currentData.classes = cloudClasses
                        self.data = currentData
                        overwriteClassesFile(with: cloudClasses)
                    }
                    
                    self.PrimaryColor = Color(hex: theme.primary)
                    self.SecondaryColor = Color(hex: theme.secondary)
                    self.TertiaryColor = Color(hex: theme.tertiary)
                    
                    // Update timestamp for widget
                    SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
                    
                    // Re-render and save data for widget
                    self.renderWithEvents()
                    self.saveScheduleLinesWithEvents()
                    self.saveTheme()
                }
            } catch {
                print("Failed to refresh from cloud: \(error)")
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
            print("Failed to fetch schedule: \(error)")
        }
    }
    
    private func enableBackgroundAppRefresh() {
        
    }
    
    private func saveEventsToCloud() {
        eventsManager.saveToCloud(using: authManager)
    }

    private func loadEventsFromCloud() {
        eventsManager.loadFromCloud(using: authManager)
    }
    
    private func saveScheduleLinesWithEvents() {
        // Combine regular schedule lines with today's events for widget
        var allItems: [ScheduleLine] = scheduleLines
        
        let now = Time.now()
        let nowSec = now.seconds
        
        // Convert events to ScheduleLine format for widget compatibility
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: selectedDate)
        for event in todaysEvents where event.isEnabled {
            let eventLine = ScheduleLine(
                content: "",
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
        
        // Sort by start time
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
            
            // NEW: Save current day code for widget
            SharedGroup.defaults.set(dayCode, forKey: "CurrentDayCode")
            
            // NEW: Save custom events separately for widget
            let eventsData = try JSONEncoder().encode(eventsManager.events)
            SharedGroup.defaults.set(eventsData, forKey: "CustomEvents")
            
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        } catch {
            print("Encoding failed:", error)
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
