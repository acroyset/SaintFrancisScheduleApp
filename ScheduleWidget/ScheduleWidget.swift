// ScheduleWidget.swift
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
        // 1. Try to find an explicitly marked current class
        if let currentIdx = firstIndex(where: { $0.isCurrentClass }) {
            // If it's the last item, show prev + current
            if currentIdx == endIndex - 1 {
                if indices.contains(currentIdx - 1) {
                    return [self[currentIdx - 1], self[currentIdx]]
                } else {
                    return [self[currentIdx]] // only one item
                }
            }
            // Otherwise show current + next
            var out = [self[currentIdx]]
            if indices.contains(currentIdx + 1) { out.append(self[currentIdx + 1]) }
            return out
        }

        // 2. No "isCurrentClass" — find the first upcoming
        if let upcomingIdx = firstIndex(where: { ($0.startSec ?? .max) > nowSec }) {
            var out = [self[upcomingIdx]]
            if indices.contains(upcomingIdx + 1) { out.append(self[upcomingIdx + 1]) }
            return out
        }

        // 3. Fallback — nothing matched, return last two or less
        return Array(suffix(2))
    }
}

@ViewBuilder
func rowView(_ line: ScheduleLine, note: String, PrimaryColor: Color, SecondaryColor: Color, TertiaryColor: Color) -> some View {
    HStack(spacing: 12) {
        // NEW: progress bar (only if we have a progress value)
        if let p = line.progress {
            ClassProgressBar(
                progress: p,
                active: line.isCurrentClass,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
                .frame(width: 6)               // slim left bar
        }
        
        // existing content...
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
                    // (optional) minutes left display
                    if let end = line.endSec, let start = line.startSec {
                        let now = Time.now().seconds
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

// MARK: - Provider
private func loadScheduleLines() -> [ScheduleLine] {
    guard let data = UserDefaults(suiteName: SharedGroup.id)?
                        .data(forKey: SharedGroup.key) else { return [] }
    return (try? JSONDecoder().decode([ScheduleLine].self, from: data)) ?? []
}

private func loadThemeColors() -> ThemeColors? {
    guard let data = SharedGroup.defaults.data(forKey: "ThemeColors") else { return nil }
    return try? JSONDecoder().decode(ThemeColors.self, from: data)
}


struct SimpleEntry: TimelineEntry {
    let date: Date
    let lines: [ScheduleLine]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), lines: [])                     // mock
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), lines: loadScheduleLines()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let lines = loadScheduleLines()
        let now = Date()

        let entry = SimpleEntry(date: now, lines: lines)

        // Wake at the next :00 second (start of next minute)
        let cal = Calendar.current
        let next = cal.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)

        completion(Timeline(entries: [entry], policy: .after(next)))
    }
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

// MARK: - Widget View
    
struct ScheduleWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        let nowSec = secondsSinceMidnight()
        let display = entry.lines.currentAndNextOrPrev(nowSec: nowSec)
        
        let theme = loadThemeColors()
        
        let PrimaryColor   = Color(hex: theme?.primary ??   "#0A84FFFF")
        let SecondaryColor = Color(hex: theme?.secondary ?? "#0A83FF19")
        let TertiaryColor  = Color(hex: theme?.tertiary ??  "#FFFFFFFF")
        
        VStack(alignment: .leading, spacing: 6) {
            ForEach(display) { line in
                rowView(line, note: "",
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor)
            }
        }
        .modifier(WidgetBackground(background: TertiaryColor))
    }
}

// MARK: - Background Helper
private struct WidgetBackground: ViewModifier {
    var background: Color
    
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .containerBackground(for: .widget) {
                    Rectangle().fill(background) // system background
                }
        } else {
            content.background(Color.clear) // iOS 14–16 fallback
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
        .description("Shows a message and the current time.")
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

