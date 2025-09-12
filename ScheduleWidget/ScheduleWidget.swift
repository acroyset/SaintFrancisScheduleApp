// Enhanced ScheduleWidget.swift
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
                // Update current class status based on time
                updatedLine.isCurrentClass = nowSec >= start && nowSec < end
            }
            return updatedLine
        }
        
        // 1. Try to find current class based on time
        if let currentIdx = updatedLines.firstIndex(where: { $0.isCurrentClass }) {
            // If it's the last item, show prev + current
            if currentIdx == endIndex - 1 {
                if indices.contains(currentIdx - 1) {
                    return [updatedLines[currentIdx - 1], updatedLines[currentIdx]]
                } else {
                    return [updatedLines[currentIdx]]
                }
            }
            // Otherwise show current + next
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

// MARK: - Enhanced Provider with Smart Updates
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), lines: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), lines: loadScheduleLines()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let lines = loadScheduleLines()
        let now = Date()
        let nowSec = secondsSinceMidnight(now)
        
        var entries: [SimpleEntry] = []
        let cal = Calendar.current
        
        // Create multiple timeline entries for the next few hours
        for minuteOffset in stride(from: 0, to: 240, by: 1) { // Update every minute for 4 hours
            let entryDate = cal.date(byAdding: .minute, value: minuteOffset, to: now) ?? now
            entries.append(SimpleEntry(date: entryDate, lines: lines))
        }
        
        // Determine next significant update time
        let nextUpdateTime = determineNextUpdateTime(lines: lines, now: now)
        
        // Request app refresh if data is stale
        let timeline = Timeline(
            entries: entries,
            policy: .after(nextUpdateTime)
        )
        
        completion(timeline)
        
        // Try to trigger background app refresh if data seems stale
        requestBackgroundAppRefresh()
    }
    
    private func determineNextUpdateTime(lines: [ScheduleLine], now: Date) -> Date {
        let nowSec = secondsSinceMidnight(now)
        let cal = Calendar.current
        
        // Find the next class start or end time
        let upcomingTimes = lines.compactMap { line -> Date? in
            guard let start = line.startSec, let end = line.endSec else { return nil }
            
            let today = cal.startOfDay(for: now)
            if start > nowSec {
                // Next class starts
                return cal.date(byAdding: .second, value: start, to: today)
            } else if end > nowSec {
                // Current class ends
                return cal.date(byAdding: .second, value: end, to: today)
            }
            return nil
        }.sorted()
        
        // Update at the next significant time, or in 15 minutes if nothing found
        return upcomingTimes.first ?? cal.date(byAdding: .minute, value: 15, to: now) ?? now
    }
    
    private func requestBackgroundAppRefresh() {
        // This will hint to the system that the widget wants fresh data
        // The system may choose to launch your app in the background
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        
        // Store when we last requested an update to avoid spam
        let lastUpdate = SharedGroup.defaults.object(forKey: "LastWidgetUpdate") as? Date ?? Date.distantPast
        let now = Date()
        
        if now.timeIntervalSince(lastUpdate) > 300 { // 5 minutes minimum between requests
            SharedGroup.defaults.set(now, forKey: "LastWidgetUpdate")
            
            // You could also store a flag that the main app checks
            SharedGroup.defaults.set(true, forKey: "WidgetRequestsUpdate")
        }
    }
}

// MARK: - Enhanced Entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    let lines: [ScheduleLine]
    
    // Add computed property to check if data is stale
    var isDataStale: Bool {
        let lastAppUpdate = SharedGroup.defaults.object(forKey: "LastAppDataUpdate") as? Date ?? Date.distantPast
        return Date().timeIntervalSince(lastAppUpdate) > 1800 // 30 minutes
    }
}

// MARK: - Enhanced Widget View
struct ScheduleWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        let nowSec = secondsSinceMidnight(entry.date)
        let display = entry.lines.currentAndNextOrPrev(nowSec: nowSec)
        
        let theme = loadThemeColors()
        
        let PrimaryColor = Color(hex: theme?.primary ?? "#0A84FFFF")
        let SecondaryColor = Color(hex: theme?.secondary ?? "#0A83FF19")
        let TertiaryColor = Color(hex: theme?.tertiary ?? "#FFFFFFFF")
        
        VStack(alignment: .leading, spacing: 6) {
            if display.isEmpty {
                // Show placeholder when no data
                VStack {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundColor(PrimaryColor)
                    Text("No schedule data")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PrimaryColor)
                    Text("Open app to sync")
                        .font(.system(size: 12))
                        .foregroundColor(PrimaryColor.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                
                // Show data age indicator if stale
                if entry.isDataStale {
                    HStack {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10))
                        Text("Data may be outdated")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(PrimaryColor.opacity(0.6))
                    .padding(.top, 2)
                }
            }
        }
        .modifier(WidgetBackground(background: TertiaryColor))
    }
}

// MARK: - Row View with Real-time Updates
@ViewBuilder
func rowView(_ line: ScheduleLine, note: String, PrimaryColor: Color, SecondaryColor: Color, TertiaryColor: Color) -> some View {
    HStack(spacing: 12) {
        // Progress bar with real-time updates
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
                    
                    // Real-time minutes left calculation
                    if let end = line.endSec, let start = line.startSec {
                        let now = secondsSinceMidnight()
                        let remainMin = max(0, (end - now) / 60)
                        if line.isCurrentClass && remainMin > 0 {
                            Text("• \(remainMin)m left")
                                .font(.system(
                                    size: 15,
                                    weight: line.isCurrentClass ? .bold : .regular,
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
                        size: 14,
                        weight: line.isCurrentClass ? .bold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(
                        line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
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
            content.background(Color.clear)
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
struct ScheduleWidget_Previews: PreviewProvider {
    static var previews: some View {
        ScheduleWidgetEntryView(entry: SimpleEntry(date: .now, lines: []))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
