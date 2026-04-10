//
//  DayTypeWidget.swift
//  Schedule
//
//  Created by Andreas Royset on 1/22/26.
//

import WidgetKit
import SwiftUI

struct DayTypeEntry: TimelineEntry {
    let date: Date
    let dayCode: String
    let dayName: String
    let schoolStartTime: String
    let isTomorrow: Bool
    let hasClasses: Bool
    let emptyMessage: String?
    let themeColors: ThemeColors?
}

struct DayTypeProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayTypeEntry {
        DayTypeEntry(date: Date(), dayCode: "G1", dayName: "Gold 1", schoolStartTime: "9:00 AM", isTomorrow: false, hasClasses: true, emptyMessage: nil, themeColors: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayTypeEntry) -> Void) {
        let (dayCode, dayName, startTime, isTomorrow, hasClasses, emptyMessage) = getDayInfo()
        completion(DayTypeEntry(date: Date(), dayCode: dayCode, dayName: dayName,
                                schoolStartTime: startTime, isTomorrow: isTomorrow, hasClasses: hasClasses,
                                emptyMessage: emptyMessage,
                                themeColors: loadThemeColors()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayTypeEntry>) -> Void) {
        let now = Date()
        let (dayCode, dayName, startTime, isTomorrow, hasClasses, emptyMessage) = getDayInfo()
        let theme = loadThemeColors()   // ← capture once at generation time

        let entry = DayTypeEntry(date: now, dayCode: dayCode, dayName: dayName,
                                 schoolStartTime: startTime, isTomorrow: isTomorrow, hasClasses: hasClasses,
                                 emptyMessage: emptyMessage,
                                 themeColors: theme)

        var nextMidnight = Calendar.current.startOfDay(for: now)
        nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: nextMidnight)!

        let timeline = Timeline(entries: [entry], policy: .after(nextMidnight))
        completion(timeline)
    }
    
    private func getDayInfo() -> (String, String, String, Bool, Bool, String?) {
        let now = Date()
        let nowSec = secondsSinceMidnight(now)
        
        guard let scheduleDict = loadScheduleDict(),
              let data = loadScheduleData() else {
            return ("", "No Schedule", "--:--", false, false, nil)
        }
        
        // Check if there are any classes left today
        let todayDateKey = getKeyForDate(now)
        let hasClassesLeft = hasRemainingClasses(dateKey: todayDateKey, scheduleDict: scheduleDict, data: data, nowSec: nowSec)
        
        // Determine which day to display
        let isTomorrow = !hasClassesLeft
        let targetDate = hasClassesLeft ? now : Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let dateKey = getKeyForDate(targetDate)
        
        guard let dayInfo = scheduleDict[dateKey],
              dayInfo.count >= 1 else {
            let nextClassText = nextWidgetClassDate(after: targetDate, scheduleDict: scheduleDict, data: data)
                .map { formattedWidgetNextClassText(for: $0, relativeTo: now) }
            return ("", "No Classes", "--:--", isTomorrow, false, nextClassText)
        }
        
        let dayCode = dayInfo[0]
        let dayName = getDayName(dayCode)
        let startTime = getSchoolStartTime(dayCode: dayCode, data: data)
        let hasClasses = startTime != "--:--"
        let emptyMessage = hasClasses
            ? nil
            : nextWidgetClassDate(after: targetDate, scheduleDict: scheduleDict, data: data)
                .map { formattedWidgetNextClassText(for: $0, relativeTo: now) }
        
        return (dayCode, dayName, startTime, isTomorrow, hasClasses, emptyMessage)
    }
    
    private func hasRemainingClasses(dateKey: String, scheduleDict: [String: [String]], data: ScheduleData, nowSec: Int) -> Bool {
        guard let dayInfo = scheduleDict[dateKey],
              dayInfo.count >= 1 else {
            return false
        }
        
        let dayCode = dayInfo[0]
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            return false
        }
        
        let day = data.days[di]
        
        // Check if any class starts after current time
        for i in day.names.indices {
            let start = day.startTimes[i]
            if start.seconds > nowSec {
                return true
            }
        }
        
        return false
    }
    
    private func getSchoolStartTime(dayCode: String, data: ScheduleData) -> String {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let di = map[dayCode.lowercased()], data.days.indices.contains(di) else {
            return "--:--"
        }
        
        let day = data.days[di]
        
        // Find first $1, $2, or $6 class
        for i in day.names.indices {
            let name = day.names[i]
            if name.hasPrefix("$") {
                if let num = Int(name.dropFirst()),
                   (num == 1 || num == 2 || num == 6) {
                    return day.startTimes[i].string()
                }
            }
        }
        
        // Fallback to first class if no $1, $2, or $6 found
        if day.names.indices.contains(0) {
            return day.startTimes[0].string()
        }
        
        return "--:--"
    }
    
    private func getDayName(_ dayCode: String) -> String {
        let codeMap: [String: String] = [
            "g1": "Gold 1",
            "b1": "Brown 1",
            "g2": "Gold 2",
            "b2": "Brown 2",
            "a1": "Activity 1",
            "a2": "Activity 2",
            "a3": "Activity 3",
            "a4": "Activity 4",
            "l1": "Liturgy 1",
            "l2": "Liturgy 2",
            "s1": "Special"
        ]
        return codeMap[dayCode.lowercased()] ?? dayCode
    }
}

struct DayTypeEntryView: View {
    var entry: DayTypeProvider.Entry
    @Environment(\.widgetFamily) var family

    private var compactEmptyDateText: String? {
        entry.emptyMessage?.replacingOccurrences(of: "Next class on ", with: "")
    }
    
    var body: some View {
        let PrimaryColor  = Color(hex: entry.themeColors?.primary  ?? "#0A84FFFF")
        let TertiaryColor = Color(hex: entry.themeColors?.tertiary ?? "#FFFFFFFF")
        
        VStack(spacing: 8) {
            if entry.isTomorrow && !entry.hasClasses {
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(TertiaryColor.opacity(0.9))
                Text("Next Class")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TertiaryColor.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(compactEmptyDateText ?? "No Classes")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(TertiaryColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                Spacer()
            } else {
                Text(entry.isTomorrow ? "Tomorrow is" : "Today is")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(TertiaryColor.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                
                Text(entry.dayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(TertiaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                
                Text(entry.dayCode.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(TertiaryColor.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Divider()
                    .background(TertiaryColor.opacity(0.3))
                
                Text("Starting at")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TertiaryColor.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                
                Text(entry.schoolStartTime)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(TertiaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .padding(.vertical, 16)
        .containerBackground(for: .widget) {
            PrimaryColor
        }
    }
}

struct DayTypeWidget: Widget {
    let kind: String = "DayTypeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayTypeProvider()) { entry in
            DayTypeEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Day Type")
        .description("Shows what type of day it is (Gold 1, Blue 2, etc.)")
        .supportedFamilies([.systemSmall])
    }
}
