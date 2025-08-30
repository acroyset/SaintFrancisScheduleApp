//
//  ContentView.swift (Updated with Firebase)
//  Schedule
//

import SwiftUI
import Foundation

var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

// Updated ToolBar with Profile button
private struct ToolBar: View {
    @Binding var window: Int
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    let tools = ["Home", "News", "Edit Classes", "Settings", "Profile"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                    Button {
                        window = index
                    } label: {
                        Text(tool)
                            .font(.system(
                                size: iPad ? 32 : 16,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .foregroundColor(window == index ? TertiaryColor : PrimaryColor)
                            .multilineTextAlignment(.trailing)
                            .padding(12)
                            .background(window == index ? PrimaryColor : SecondaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal) // optional: adds padding on left/right
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
    
    @State private var window: Int = 0
    // 0 = Home
    // 1 = News
    // 2 = Class Editor
    // 3 = Settings
    // 4 = Prifile View
    
    @State private var PrimaryColor: Color = .blue
    @State private var SecondaryColor: Color = .blue.opacity(0.1)
    @State private var TertiaryColor: Color = .white
    
    @State private var isPortrait: Bool = !iPad
    @State private var hasLoadedFromCloud = false
    
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
                }
            })
            
            VStack {
                
                Text("Version - Beta 1.4\nBugs / Ideas - Email acroyset@gmail.com")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .onTapGesture(perform: {
                    withAnimation(.snappy){
                        showCalendarGrid = false;
                        whatsNewPopup = false
                    }
                })
                
                if window == 0 {
                    VStack {
                        dayHeaderView(
                            dayInfo: getDayInfo(for: dayCode),
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor
                        )
                        .onTapGesture(perform: {
                            withAnimation(.snappy){
                                showCalendarGrid = false;
                                whatsNewPopup = false
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
                        
                        ClassItemScroll()
                            .onTapGesture(perform: {
                                withAnimation(.snappy){
                                    showCalendarGrid = false;
                                    whatsNewPopup = false
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
                
                else if window == 1 {
                    NewsMenu(
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                }
                
                else if window == 2 {
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
                }
                
                else if window == 3 {
                    Settings(
                        PrimaryColor: $PrimaryColor,
                        SecondaryColor: $SecondaryColor,
                        TertiaryColor: $TertiaryColor,
                        isPortrait: isPortrait
                    )
                }
                
                else if window == 4 {
                    ProfileMenu(
                        data: $data,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
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
                    
                    Text("- Cloud Syncing With Email\n- News Tab\n- Expanded Schedule Abilities\n- Bug Fixes")
                        .font(.system(
                            size: iPad ? 24 : 15,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                        .frame(alignment: .leading)
                }
                .frame(maxWidth: iPad ? 500 : 300)
                .background(TertiaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(radius: 20)
            }
        }
        
        .padding()
        .animation(.easeInOut(duration: 0.3), value: dayCode)
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
            setScroll()
            saveClassesToCloud()
            window = 0
            applySelectedDate(Date())
        }
        .onChange(of: window) { oldWindow, newWindow in
            guard oldWindow != newWindow else { return }
            withAnimation(.snappy){
                showCalendarGrid = false;
            }
        }
        .onReceive(ticker) { _ in
            render()
            setIsPortrait()
        }
    }
    
    // MARK: - View builders (same as before)
    @ViewBuilder
    private func ClassItemScroll() -> some View {
        ScrollView {
            VStack(spacing: 8) {
                if !output.isEmpty && scheduleLines.isEmpty {
                    Text(output)
                        .font(.system(
                            size: iPad ? 35 : 17,
                            design: .monospaced
                        ))
                        .foregroundColor(PrimaryColor)
                }
                
                ForEach(Array(scheduleLines.enumerated()), id: \.0) { i, line in
                    rowView(
                        line,
                        note : note,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .id(i)
                }
            }
            .padding(.horizontal)
        }
        .id(dayCode)
        .scrollPosition(id: $scrollTarget, anchor: .center)
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
                let cloudClasses = try await dataManager.loadClasses(for: user.id)
                if !cloudClasses.isEmpty {
                    DispatchQueue.main.async {
                        if var currentData = self.data {
                            currentData.classes = cloudClasses
                            self.data = currentData
                        }
                        self.hasLoadedFromCloud = true
                        // Also save to local file as backup
                        self.overwriteClassesFile(with: cloudClasses)
                    }
                }
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
                try await dataManager.saveClasses(classes, for: user.id)
                // Also save locally as backup
                DispatchQueue.main.async {
                    self.overwriteClassesFile(with: classes)
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
            var start   = d.startTimes[i]
            var end     = d.endTimes[i]
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
                    end = start
                    start = d.endTimes[i-1]
                    let p = progressValue(start: start.seconds, end: end.seconds, now: nowSec)
                    scheduleLines.append(ScheduleLine(
                        content: "",
                        isCurrentClass: true,
                        timeRange: "\(start.string()) to \(end.string())",
                        className: "Passing Period",
                        startSec: start.seconds,
                        endSec: end.seconds,
                        progress: p
                    ))
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
    
    private func overwriteClassesFile(with classes: [ClassItem]) {
        do {
            let url = try ensureWritableClassesFile()
            let text = classes.map { "\($0.name) - \($0.teacher) - \($0.room)" }
                              .joined(separator: "\n") + "\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("overwriteClassesFile error:", error)
        }
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
    
    private func classesDocumentsURL() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent("Classes.txt")
    }

    @discardableResult
    private func ensureWritableClassesFile() throws -> URL {
        let dst = try classesDocumentsURL()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dst.path) {
            if let src = Bundle.main.url(forResource: "Classes", withExtension: "txt") {
                try? fm.copyItem(at: src, to: dst)
            } else {
                try "".write(to: dst, atomically: true, encoding: .utf8)
            }
        }
        return dst
    }
    
    private func setIsPortrait() -> Void {
        let width = UIScreen.main.bounds.width
        let height = UIScreen.main.bounds.height
        isPortrait = height > width
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
