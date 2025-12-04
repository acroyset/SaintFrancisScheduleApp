//
//  RowView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/19/25.
//

import SwiftUI


@ViewBuilder
func rowView(
    _ line: ScheduleLine,
    note: String,
    date: Date,
    PrimaryColor: Color,
    SecondaryColor: Color,
    TertiaryColor: Color
) -> some View {
    HStack(spacing: 12) {
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
                    
                    if let end = line.endSec, let start = line.startSec {
                        let now = secondsSinceMidnight(date)
                        let remainMin = max(0, (end - now) / 60)
                        let isCurrentlyActive = (now >= start && now < end)
                        if isCurrentlyActive && remainMin > 0 {
                            Text("• \(remainMin)m left")
                                .font(.system(
                                    size: 15,
                                    weight: line.isCurrentClass ? .bold : .regular,
                                    design: .monospaced
                                ))
                                .foregroundStyle(TertiaryColor.opacity(0.9))
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
