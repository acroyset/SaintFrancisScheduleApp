// Enhanced ScheduleWidget.swift with Auto-updating Schedule
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

private func secondsSinceMidnight(_ date: Date = Date()) -> Int {
    let cal = Calendar.current
    let comps = cal.dateComponents([.hour, .minute, .second], from: date)
    return (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
}

private extension Array where Element == ScheduleLine {
    func currentAndNextOrPrev(nowSec: Int) -> [ScheduleLine] {
        // Update progress values in real-time for current classes
        var updatedLines = self.map { line -> ScheduleLine in
            var updatedLine = line
            if let start = line.startSec, let end = line.endSec {
                let progress = progressValue(start: start, end: end, now: nowSec)
                updatedLine.progress = progress
                updatedLine.isCurrentClass = nowSec >= start && nowSec < end
            }
            return updatedLine
        }
        
        // 1. Try to find current class based on time
        if let currentIdx = updatedLines.firstIndex(where: { $0.isCurrentClass }) {
            if currentIdx == endIndex - 1 {
                if indices.contains(currentIdx - 1) {
                    return [updatedLines[currentIdx - 1], updatedLines[currentIdx]]
                } else {
                    return [updatedLines[currentIdx]]
                }
            }
            var out = [updatedLines[currentIdx]]
            if indices.contains(currentIdx + 1) { out.append(updatedLines[currentIdx + 1]) }
            return out
        }

        // 2. No current class — find the first upcoming
        if let upcomingIdx = updatedLines.firstIndex(where: { ($0.startSec ?? .max) > nowSec }) {
            var out = [updatedLines[upcomingIdx]]
            if indices.contains(upcomingIdx + 1) { out.append(updatedLines[upcomingIdx + 1]) }
            return out
        }

        // 3. Fallback — return last two or less
        return Array(updatedLines.suffix(2))
    }
}

// MARK: - Enhanced Provider with Daily Updates
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), lines: [], dayCode: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let (lines, dayCode) = loadTodaysSchedule()
        completion(SimpleEntry(date: Date(), lines: lines, dayCode: dayCode))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        
        // Get today's schedule
        let (lines, dayCode) = loadTodaysSchedule()
        
        var entries: [SimpleEntry] = []
        let nowSec = secondsSinceMidnight(now)
        
        entries.append(SimpleEntry(date: now, lines: lines, dayCode: dayCode))
        
        let today = cal.startOfDay(for: now)
        
        for line in lines {
            guard let startSec = line.startSec, let endSec = line.endSec else { continue }
            
            // Class start
            if startSec > nowSec {
                let startTime = today.addingTimeInterval(TimeInterval(startSec))
                entries.append(SimpleEntry(date: startTime, lines: lines, dayCode: dayCode))
            }
            
            // Class end
            if endSec > nowSec {
                let endTime = today.addingTimeInterval(TimeInterval(endSec))
                entries.append(SimpleEntry(date: endTime, lines: lines, dayCode: dayCode))
            }
            
            // During current class: add update every 5 minutes
            if nowSec >= startSec && nowSec < endSec {
                var nextMin = ((nowSec / 300) + 1) * 300 // Next 5-min mark
                while nextMin < endSec {
                    let updateTime = today.addingTimeInterval(TimeInterval(nextMin))
                    if updateTime > now {
                        entries.append(SimpleEntry(date: updateTime, lines: lines, dayCode: dayCode))
                    }
                    nextMin += 300 // Every 5 minutes
                }
            }
        }
        
        // 3. Remove duplicates and sort
        let uniqueEntries = Dictionary(grouping: entries) { $0.date }
            .map { $0.value.first! }
            .sorted { $0.date < $1.date }
        
        entries = uniqueEntries
        
        // 4. Determine next major refresh (midnight for new day)
        var nextMajorUpdate = cal.startOfDay(for: now)
        nextMajorUpdate = cal.date(byAdding: .day, value: 1, to: nextMajorUpdate)!
        
        // Also consider next class event if sooner
        if let nextClassTime = entries.dropFirst().first?.date,
           nextClassTime < nextMajorUpdate {
            nextMajorUpdate = nextClassTime
        }
        
        // Create timeline with smart refresh policy
        let timeline = Timeline(
            entries: entries.isEmpty ? [SimpleEntry(date: now, lines: lines, dayCode: dayCode)] : entries,
            policy: .after(nextMajorUpdate)
        )
        
        completion(timeline)
    }
    
    private func loadTodaysSchedule() -> ([ScheduleLine], String) {
        let now = Date()
        
        // 1. Get the schedule dictionary from shared storage
        guard let scheduleDict = loadScheduleDict() else {
            print("❌ Widget: Failed to load schedule dictionary")
            return ([], "")
        }
        
        // 2. Get today's date key
        let dateKey = getKeyForDate(now)
        
        // 3. Get today's day code
        guard let dayInfo = scheduleDict[dateKey],
              dayInfo.count >= 1 else {
            print("❌ Widget: No schedule for \(dateKey)")
            return ([], "")
        }
        
        let dayCode = dayInfo[0]
        
        // 4. Load the class data
        guard let data = loadScheduleData() else {
            print("❌ Widget: Failed to load schedule data")
            return ([], dayCode)
        }
        
        // 5. Generate schedule lines for today
        let lines = generateScheduleLines(for: dayCode, data: data, date: now)
        
        return (lines, dayCode)
    }
    
    private func generateScheduleLines(for dayCode: String, data: ScheduleData, date: Date) -> [ScheduleLine] {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            return []
        }
        
        let day = data.days[di]
        let now = Time.now()
        let nowSec = now.seconds
        
        // Check if we need to swap lunch and period 4/5
        let shouldSwap = shouldSwapLunchAndPeriod(dayIndex: di, isSecondLunch: data.isSecondLunch)
        
        var lines: [ScheduleLine] = []
        
        for i in day.names.indices {
            let nameRaw = day.names[i]
            var start = day.startTimes[i]
            var end = day.endTimes[i]
            
            // Apply second lunch override
            if shouldSwap {
                if nameRaw == "Lunch" {
                    start = Time(h: 12, m: 25, s: 0)
                    end = Time(h: 13, m: 5, s: 0)
                } else if nameRaw.contains("$4") || nameRaw.contains("$5") ||
                          nameRaw.contains("Period 4") || nameRaw.contains("Period 5") {
                    start = Time(h: 11, m: 0, s: 0)
                    end = Time(h: 12, m: 20, s: 0)
                }
            }
            
            let isCurrentClass = (start <= now && now < end) && Calendar.current.isDateInToday(date)
            
            // Handle class references ($1, $2, etc.)
            if nameRaw.hasPrefix("$"),
               let idx = Int(nameRaw.dropFirst()),
               (1...data.classes.count).contains(idx) {
                let c = data.classes[idx-1]
                let teacher = (c.teacher == "N" || c.teacher.isEmpty) ? "" : c.teacher
                let room = (c.room == "N" || c.room.isEmpty) ? "" : c.room
                
                let p = progressValue(start: start.seconds, end: end.seconds, now: nowSec)
                
                lines.append(ScheduleLine(
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
                ))
            } else {
                lines.append(ScheduleLine(
                    content: "",
                    base: nameRaw,
                    isCurrentClass: isCurrentClass,
                    timeRange: "\(start.string()) to \(end.string())",
                    className: nameRaw,
                    startSec: start.seconds,
                    endSec: end.seconds
                ))
            }
        }
        
        return lines
    }
    
    private func shouldSwapLunchAndPeriod(dayIndex: Int, isSecondLunch: Bool) -> Bool {
        let daysWithLunchPeriod = [0, 1, 2, 3, 4, 5]
        return isSecondLunch && daysWithLunchPeriod.contains(dayIndex)
    }
}

// MARK: - Data Loading Functions

private func loadScheduleDict() -> [String: [String]]? {
    guard let data = SharedGroup.defaults.data(forKey: "ScheduleDict") else {
        return nil
    }
    return try? JSONDecoder().decode([String: [String]].self, from: data)
}

private func loadScheduleData() -> ScheduleData? {
    // Try to load from shared defaults (saved by main app)
    guard let classesData = SharedGroup.defaults.data(forKey: "ScheduleClasses"),
          let daysData = SharedGroup.defaults.data(forKey: "ScheduleDays") else {
        return nil
    }
    
    guard let classes = try? JSONDecoder().decode([ClassItem].self, from: classesData),
          let days = try? JSONDecoder().decode([Day].self, from: daysData) else {
        return nil
    }
    
    let isSecondLunch = SharedGroup.defaults.bool(forKey: "IsSecondLunch")
    
    return ScheduleData(classes: classes, days: days, isSecondLunch: isSecondLunch)
}

private func getKeyForDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd-yy"
    return formatter.string(from: date)
}

// MARK: - Enhanced Entry
struct SimpleEntry: TimelineEntry, Hashable {
    let date: Date
    let lines: [ScheduleLine]
    let dayCode: String
    
    var isDataStale: Bool {
        let lastAppUpdate = SharedGroup.defaults.object(forKey: "LastAppDataUpdate") as? Date ?? Date.distantPast
        return Date().timeIntervalSince(lastAppUpdate) > 1800 // 30 minutes
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(dayCode)
    }
    
    static func == (lhs: SimpleEntry, rhs: SimpleEntry) -> Bool {
        return lhs.date == rhs.date && lhs.dayCode == rhs.dayCode
    }
}

// MARK: - Enhanced Widget View
struct ScheduleWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let nowSec = secondsSinceMidnight(entry.date)
        let display = entry.lines.currentAndNextOrPrev(nowSec: nowSec)
        
        let theme = loadThemeColors()
        
        let PrimaryColor = Color(hex: theme?.primary ?? "#0A84FFFF")
        let SecondaryColor = Color(hex: theme?.secondary ?? "#0A83FF19")
        let TertiaryColor = Color(hex: theme?.tertiary ?? "#FFFFFFFF")
        
        VStack(alignment: .leading, spacing: 6) {
            // Show day code
            if display.isEmpty {
                emptyScheduleView(
                    dayCode: entry.dayCode,
                    PrimaryColor: PrimaryColor
                )
            } else {
                ForEach(display) { line in
                    rowView(
                        line,
                        note: "",
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                }
                
                if false && entry.isDataStale {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text("Open app to refresh")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(PrimaryColor.opacity(0.6))
                    .padding(.top, 2)
                }
            }
        }
        .modifier(WidgetBackground(background: TertiaryColor))
    }
    
    @ViewBuilder
    private func emptyScheduleView(dayCode: String, PrimaryColor: Color) -> some View {
        VStack {
            if !dayCode.isEmpty {
                Text(dayCode.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(PrimaryColor.opacity(0.7))
                    .padding(.bottom, 2)
            }
            
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(PrimaryColor)
                .font(.title2)
            Text("No Classes Today")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PrimaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row View
@ViewBuilder
func rowView(_ line: ScheduleLine, note: String, PrimaryColor: Color, SecondaryColor: Color, TertiaryColor: Color) -> some View {
    HStack(spacing: 12) {
        if let p = line.progress {
            ClassProgressBar(
                progress: p,
                active: line.isCurrentClass,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            .frame(width: 6)
        }
        
        if !line.timeRange.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.timeRange)
                    .font(.system(
                        size: 14,
                        weight: line.isCurrentClass ? .bold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(
                        line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                
                HStack(spacing: 6) {
                    let name = line.className == "Activity" ? note : line.className
                    let x = name == "" ? "Unknown" : name
                    Text(x)
                        .font(.system(
                            size: 17,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .foregroundStyle(
                            line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                        .lineLimit(1)
                    
                    if let end = line.endSec, let start = line.startSec {
                        let now = secondsSinceMidnight()
                        let remainMin = max(0, (end - now) / 60)
                        if line.isCurrentClass && remainMin > 0 {
                            Text("• \(remainMin)m")
                                .font(.system(
                                    size: 13,
                                    weight: .semibold,
                                    design: .monospaced
                                ))
                                .foregroundStyle(
                                    line.isCurrentClass ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.7))
                        }
                    }
                }
            }
            
            Spacer()
            
            if !line.room.isEmpty {
                Text(line.room)
                    .font(.system(
                        size: 13,
                        weight: line.isCurrentClass ? .bold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(
                        line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                    .lineLimit(1)
            }
        } else {
            Text(line.content)
                .font(.system(
                    size: 16,
                    weight: .bold,
                    design: .monospaced
                ))
                .foregroundStyle(
                    line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
            Spacer()
        }
    }
    .padding(12)
    .background(line.isCurrentClass ? PrimaryColor : SecondaryColor)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
}

// MARK: - Helper Functions
private func loadScheduleLines() -> [ScheduleLine] {
    guard let data = UserDefaults(suiteName: SharedGroup.id)?
                        .data(forKey: SharedGroup.key) else { return [] }
    return (try? JSONDecoder().decode([ScheduleLine].self, from: data)) ?? []
}

private func loadThemeColors() -> ThemeColors? {
    guard let data = SharedGroup.defaults.data(forKey: "ThemeColors") else { return nil }
    return try? JSONDecoder().decode(ThemeColors.self, from: data)
}

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
        case 8:
            r = Double((int & 0xFF000000) >> 24) / 255
            g = Double((int & 0x00FF0000) >> 16) / 255
            b = Double((int & 0x0000FF00) >> 8) / 255
            a = Double(int & 0x000000FF) / 255
        case 6:
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

// MARK: - Background Helper
private struct WidgetBackground: ViewModifier {
    var background: Color
    
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .containerBackground(for: .widget) {
                    Rectangle().fill(background)
                }
        } else {
            content.background(background)
        }
    }
}

// MARK: - Widget Config
@main
struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Schedule Widget")
        .description("Shows your current and upcoming classes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview
#Preview(as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    SimpleEntry(date: .now, lines: [], dayCode: "G1")
}
