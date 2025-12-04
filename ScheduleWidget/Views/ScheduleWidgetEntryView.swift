//
//  ScheduleWidgetEntryView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import WidgetKit
import SwiftUI

func secondsSinceMidnight(_ date: Date = Date()) -> Int {
    let cal = Calendar.current
    let comps = cal.dateComponents([.hour, .minute, .second], from: date)
    return (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
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
                        date: entry.date,
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
