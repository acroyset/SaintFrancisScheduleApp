//
//  ScheduleWidgetEntryView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import WidgetKit
import SwiftUI

private func secondsSinceMidnight(_ date: Date = Date()) -> Int {
    let cal = Calendar.current
    let comps = cal.dateComponents([.hour, .minute, .second], from: date)
    return (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
}

extension Array where Element == ScheduleLine {
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

private func loadThemeColors() -> ThemeColors? {
    guard let data = SharedGroup.defaults.data(forKey: "ThemeColors") else { return nil }
    return try? JSONDecoder().decode(ThemeColors.self, from: data)
}

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
