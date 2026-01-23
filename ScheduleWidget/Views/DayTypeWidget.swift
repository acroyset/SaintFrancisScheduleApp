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
}

struct DayTypeProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayTypeEntry {
        DayTypeEntry(date: Date(), dayCode: "G1", dayName: "Gold 1", schoolStartTime: "8:45 AM")
    }

    func getSnapshot(in context: Context, completion: @escaping (DayTypeEntry) -> Void) {
        let (dayCode, dayName, startTime) = getTodaysDayInfo()
        completion(DayTypeEntry(date: Date(), dayCode: dayCode, dayName: dayName, schoolStartTime: startTime))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayTypeEntry>) -> Void) {
        let now = Date()
        let (dayCode, dayName, startTime) = getTodaysDayInfo()
        
        let entry = DayTypeEntry(date: now, dayCode: dayCode, dayName: dayName, schoolStartTime: startTime)
        
        // Refresh at midnight
        var nextMidnight = Calendar.current.startOfDay(for: now)
        nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: nextMidnight)!
        
        let timeline = Timeline(entries: [entry], policy: .after(nextMidnight))
        completion(timeline)
    }
    
    private func getTodaysDayInfo() -> (String, String, String) {
        let now = Date()
        
        guard let scheduleDict = loadScheduleDict(),
              let data = loadScheduleData() else {
            return ("", "No Schedule", "--:--")
        }
        
        let dateKey = getKeyForDate(now)
        
        guard let dayInfo = scheduleDict[dateKey],
              dayInfo.count >= 1 else {
            return ("", "No Classes", "--:--")
        }
        
        let dayCode = dayInfo[0]
        let dayName = getDayName(dayCode)
        let startTime = getSchoolStartTime(dayCode: dayCode, data: data)
        
        return (dayCode, dayName, startTime)
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
    
    var body: some View {
        let theme = loadThemeColors()
        let PrimaryColor = Color(hex: theme?.primary ?? "#0A84FFFF")
        let TertiaryColor = Color(hex: theme?.tertiary ?? "#FFFFFFFF")
        
        VStack(spacing: 8) {
            Text("Today is a")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(TertiaryColor.opacity(0.8))
            
            Text(entry.dayName)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(TertiaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(entry.dayCode.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(TertiaryColor.opacity(0.6))
            
            Divider()
                .background(TertiaryColor.opacity(0.3))
            
            Text("Starting at")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(TertiaryColor.opacity(0.8))
            
            Text(entry.schoolStartTime)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(TertiaryColor)
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

#Preview(as: .systemSmall) {
    DayTypeWidget()
} timeline: {
    DayTypeEntry(date: .now, dayCode: "G2", dayName: "Gold 2", schoolStartTime: "8:45 AM")
}
