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
        
        let theme = loadThemeColors()
        
        let PrimaryColor = Color(hex: theme?.primary ?? "#0A84FFFF")
        let SecondaryColor = Color(hex: theme?.secondary ?? "#0A83FF19")
        let TertiaryColor = Color(hex: theme?.tertiary ?? "#FFFFFFFF")
        
        Group {
            switch family {
            case .systemSmall:
                let display = entry.lines.currentOrPrev(nowSec: nowSec)
                smallWidgetView(display, dayCode: entry.dayCode, PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor, TertiaryColor: TertiaryColor)
            default:
                let display = entry.lines.currentAndNextOrPrev(nowSec: nowSec)
                mediumLargeWidgetView(display, dayCode: entry.dayCode, date: entry.date, PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor, TertiaryColor: TertiaryColor)
            }
        }
        .modifier(WidgetBackground(background: TertiaryColor))
    }
    
    // MARK: - Small Square Widget
    @ViewBuilder
    private func smallWidgetView(
        _ line: ScheduleLine?,
        dayCode: String,
        PrimaryColor: Color,
        SecondaryColor: Color,
        TertiaryColor: Color
    ) -> some View {
        if let current = line {
            HStack(alignment: .top, spacing: 8) {
                // Progress bar - fixed width
                if let p = current.progress {
                    ClassProgressBar(
                        progress: p,
                        active: current.isCurrentClass,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    // Class name
                    Text(current.className == "Activity" ? "Activity" : current.className)
                        .font(.system(size: iPad ? 20 : 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundColor(current.isCurrentClass ? TertiaryColor : PrimaryColor)
                    
                    // Time
                    Text(current.timeRange)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(current.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                    
                    // Remaining time if current
                    if current.isCurrentClass, let endSec = current.endSec {
                        let now = secondsSinceMidnight()
                        let remaining = max(0, endSec - now)
                        let secs = remaining
                        if (secs > 60){
                            Text("\(Int(floor(Double(secs)/60.0)))m left")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .foregroundColor(TertiaryColor)
                        } else {
                            Text("\(Int(secs))s left")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .foregroundColor(TertiaryColor)
                        }
                    }
                    
                    // Room
                    if !current.room.isEmpty {
                        Text(current.room)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(current.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                    }
                    
                    Spacer()
                }
                
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(current.isCurrentClass ? PrimaryColor : TertiaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        } else {
            VStack(spacing: 8) {
                Text(dayCode.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(PrimaryColor.opacity(0.7))
                
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(PrimaryColor)
                    .font(.system(size: 24))
                
                Text("No Classes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PrimaryColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    // MARK: - Medium & Large Widget
    @ViewBuilder
    private func mediumLargeWidgetView(
        _ display: [ScheduleLine],
        dayCode: String,
        date: Date,
        PrimaryColor: Color,
        SecondaryColor: Color,
        TertiaryColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if display.isEmpty {
                emptyScheduleView(
                    dayCode: dayCode,
                    PrimaryColor: PrimaryColor
                )
            } else {
                ForEach(display) { line in
                    rowView(
                        line,
                        note: "",
                        date: date,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                }
            }
        }
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
