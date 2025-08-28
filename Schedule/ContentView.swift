//
//  ContentView.swift (Updated with Firebase)
//  Schedule
//

import SwiftUI
import Foundation
import WidgetKit

var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

// Add profile menu view
private struct ProfileMenu: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var dataManager = DataManager()
    @Binding var data: ScheduleData?
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    @State private var showingDeleteAlert = false
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Profile")
                .font(.system(
                    size: iPad ? 40 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .foregroundColor(PrimaryColor)
            
            Divider()
            
            if let user = authManager.user {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signed in as:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(user.displayName ?? "User")
                        .font(.headline)
                        .foregroundColor(PrimaryColor)
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(SecondaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Sync Status
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.green)
                Text("Classes synced to cloud")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
            
            // Manual Sync Button
            Button {
                syncClasses()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Sync Now")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding()
                .background(PrimaryColor.opacity(0.1))
                .foregroundColor(PrimaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isLoading)
            
            Spacer()
            
            // Danger Zone
            VStack(spacing: 8) {
                Text("Danger Zone")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Delete Account Button - FIXED
                Button {
                    showingDeleteAlert = true
                } label: {
                    Text("Delete Account")
                        .frame(maxWidth: .infinity, minHeight: 44) // Better touch area
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            // Sign Out Button - FIXED
            Button {
                authManager.signOut()
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity, minHeight: 44) // Better touch area
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(PrimaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black, radius: 30)
        .frame(
            maxWidth: iPad ? 600 : 300,
            maxHeight: iPad ? 600 : 500)
        .alert("Delete Account", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    deleteAccount()
                }
            }
        } message: {
            Text("This will permanently delete your account and all data. This action cannot be undone.")
        }
    }
    
    private func syncClasses() {
        guard let user = authManager.user,
              let classes = data?.classes else { return }
        
        isLoading = true
        Task {
            do {
                try await dataManager.saveClasses(classes, for: user.id)
            } catch {
                print("Failed to sync classes: \(error)")
            }
            isLoading = false
        }
    }
    
    private func deleteAccount() {
        guard let user = authManager.user else { return }
        
        Task {
            do {
                try await dataManager.deleteUserData(for: user.id)
                authManager.signOut()
            } catch {
                print("Failed to delete account: \(error)")
            }
        }
    }
}

// Updated ToolBar with Profile button
private struct ToolBar: View {
    @Binding var editClasses: Bool
    @Binding var settingsOpen: Bool
    @Binding var profileOpen: Bool
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        HStack {
            Button {
                editClasses.toggle()
            } label: {
                Text("Edit Classes")
                    .font(.system(
                        size: iPad ? 32 : 18,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundColor(PrimaryColor)
                    .multilineTextAlignment(.trailing)
                    .padding(12)
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            Button {
                settingsOpen.toggle()
            }
            label: {
                Text("Settings")
                    .font(.system(
                        size: iPad ? 32 : 18,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundColor(PrimaryColor)
                    .multilineTextAlignment(.trailing)
                    .padding(12)
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            Button {
                profileOpen.toggle()
            } label: {
                Text("Profile")
                    .font(.system(
                        size: iPad ? 32 : 18,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundColor(PrimaryColor)
                    .multilineTextAlignment(.trailing)
                    .padding(12)
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
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
    @State private var showCalendarGrid = false
    @State private var scrollTarget: Int? = nil
    @State private var editClasses: Bool = false
    @State private var settingsOpen: Bool = false
    @State private var profileOpen: Bool = false
    
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
            .onTapGesture {
                closeAll()
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
                    closeAll()
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
                .zIndex(10)
                
                Divider()
                
                ClassItemScroll()
                
                Divider()
                Spacer(minLength: 12)
                
                ToolBar(
                    editClasses: $editClasses,
                    settingsOpen: $settingsOpen,
                    profileOpen: $profileOpen,
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
            
            // Overlays
            if editClasses {
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
            
            if settingsOpen {
                Settings(
                    PrimaryColor: $PrimaryColor,
                    SecondaryColor: $SecondaryColor,
                    TertiaryColor: $TertiaryColor,
                    isPortrait: isPortrait
                )
            }
            
            if profileOpen {
                ProfileMenu(
                    data: $data,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
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
        .onTapGesture {
            closeAll()
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
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9]
        guard let di = map[currentDay.lowercased()],
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return di
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
    
    private func closeAll() -> Void {
        withAnimation(.snappy) {
            showCalendarGrid = false
            editClasses = false
            settingsOpen = false
            profileOpen = false
        }
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationManager())
    }
}
