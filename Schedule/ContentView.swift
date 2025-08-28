import SwiftUI
import Foundation
import WidgetKit


var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }


// Safe index helper (optional)
extension Array {
    subscript(safe i: Index) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

private struct ToolBar: View{
    @Binding var editClasses: Bool
    @Binding var settingsOpen: Bool
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View{
        HStack {
            Button {
                editClasses.toggle()
            }
            label: {
                Text("Edit Classes")
                    .font(.system(
                        size: iPad ? 27 : 20,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundColor(PrimaryColor)
                    .multilineTextAlignment(.trailing)
                    .padding(15)
                    .padding(.horizontal)
            }
            
            Button {
                settingsOpen.toggle()
            }
            label: {
                Text("Settings")
                    .font(.system(
                        size: iPad ? 27 : 20,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundColor(PrimaryColor)
                    .multilineTextAlignment(.trailing)
                    .padding(15)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - View
struct ContentView: View {
    @State private var output = "Loading…"
    @State private var dayCode = ""
    @State private var note = ""
    @State private var scheduleDict: [String: [String]]? = nil
    @State private var hasTriedFetchingSchedule = false
    @State private var scheduleLines: [ScheduleLine] = []
    @State private var data: ScheduleData? = nil
    @State private var selectedDate = Date()
    @State private var showCalendarGrid = false
    @State private var scrollTarget: Int? = nil
    @State private var editClasses: Bool = false
    @State private var settingsOpen: Bool = false
    
    @State private var PrimaryColor: Color = .blue
    @State private var SecondaryColor: Color = .blue.opacity(0.1)
    @State private var TertiaryColor: Color = .white
    
    @State private var isPortrait: Bool = !iPad
    
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            Background(
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
                .onTapGesture {
                    closeCalendar()
                    closeClassEditor()
                    closeSettings()
                }
            
            VStack {
                dayHeaderView(
                    for: dayCode,
                    getDayInfo: getDayInfo,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                    .onTapGesture {
                        closeCalendar()
                        closeClassEditor()
                        closeSettings()
                    }
                
                DateNavigator(
                    showCalendar: $showCalendarGrid,
                    date: $selectedDate,
                    onPick: { applySelectedDate($0)},
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .zIndex(10) // Higher z-index for calendar
                
                Divider()
                
                ClassItemScroll()
                
                Divider()
                
                ToolBar(
                    editClasses: $editClasses,
                    settingsOpen: $settingsOpen,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        if value.translation.width > threshold {
                            // Swipe right - go to previous day
                            withAnimation(.snappy) {
                                let new = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                                selectedDate = new
                                applySelectedDate(new)
                            }
                        } else if value.translation.width < -threshold {
                            // Swipe left - go to next day
                            withAnimation(.snappy) {
                                let new = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                                selectedDate = new
                                applySelectedDate(new)
                            }
                        }
                    },
                isEnabled:true
            )
            
            if editClasses {
                let bindingData = Binding<ScheduleData>(
                    get: { self.data ?? ScheduleData(classes: [], days: []) },
                    set: { self.data = $0 }
                )

                ClassEditor(
                    data: bindingData,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor,
                    isPortrait: isPortrait
                )
            }
            
            if settingsOpen {
                Settings(
                        PrimaryColor: $PrimaryColor,
                        SecondaryColor: $SecondaryColor,
                        TertiaryColor: $TertiaryColor,
                        isPortrait: isPortrait
                    )
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.3), value: dayCode)
        
        .onAppear {
            loadOnce()
            setScroll()
        }
        .onChange(of: dayCode) { oldDay, newDay in
            guard oldDay != newDay else { return }
            setScroll()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active else { return }
            setScroll()
            if let classes = data?.classes { overwriteClassesFile(with: classes) }
        }
        .onChange(of: data?.classes) { oldClasses, newClasses in guard oldClasses != newClasses else { return }
            if let classes = data?.classes { overwriteClassesFile(with: classes) }
        }
        .onReceive(ticker) {
            _ in render()
            setIsPortrait()
        }
    }
    
    // MARK: - View builders
    
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
        .onTapGesture {
            closeCalendar()
            closeClassEditor()
            closeSettings()
        }
            .id(dayCode)
            .scrollPosition(id: $scrollTarget, anchor: .center)
    }
    
    
    // MARK: - Data helpers
    
    private func getDayInfo(for currentDay: String) -> Day? {
        let di = getDayNumber(for: currentDay) ?? 0
        return data?.days[di]
    }
    
    private func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9]
        guard let di = map[currentDay.lowercased()],
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return di
    }
    
    private func loadOnce() {
        guard data == nil else { return }
        
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
    
    private func render() {
        let cal = Calendar.current
        
        let isToday = cal.isDateInToday(selectedDate)
        
        guard let data = data else { return }
        
        
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9]
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            scheduleLines = []
            if (!dayCode.isEmpty && dayCode != "None") {
                output = "Invalid day code: '\(dayCode)'. Valid codes: G1, B1, G2, B2, A1, A2, A3, A4, L1, L2"
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
                        startSec: start.seconds,               // NEW
                        endSec: end.seconds,                   // NEW
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
                    startSec: start.seconds,               // NEW
                    endSec: end.seconds,                   // NEW
                    progress: p                            // NEW
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
    
    // MARK: - Parsing / Utils
    
    private func applySelectedDate(_ date: Date) {
        selectedDate = date
        let key = getKeyToday()
        
        if let day = scheduleDict?[key] {
            dayCode = day[0]
            note = day[1]
            render()                     // rebuild rows
            DispatchQueue.main.async {   // center after rows update
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
        f.dateFormat = "MM-dd-yy"        // matches your CSV keys
        return f.string(from: selectedDate)
    }
    
    // Prefer the actual class row with a timeRange; fall back to any "current" block
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
    
    private func closeCalendar()  -> Void {
        withAnimation(.snappy) { showCalendarGrid = false }
    }
    
    private func closeClassEditor() {
        editClasses = false
    }
    
    private func closeSettings() -> Void {
        withAnimation(.snappy) { settingsOpen = false }
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

    /// Ensure we have a writable Classes.txt in Documents (copy the bundled one the first time).
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
    
    
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
