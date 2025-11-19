//
//  ScheduleRowView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct ScheduleRowView: View {
    let line: ScheduleLine
    let note: String
    let isToday: Bool
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            if let progress = line.progress {
                ClassProgressBar(
                    progress: progress,
                    active: line.isCurrentClass,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .frame(width: 6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if !line.timeRange.isEmpty {
                    Text(line.timeRange)
                        .font(.system(size: iPad ? 16 : 14, weight: .medium, design: .monospaced))
                        .foregroundColor(line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                }
                
                HStack(spacing: 8) {
                    let name = line.className == "Activity" ? note : line.className
                    Text(name.isEmpty ? "Unknown" : name)
                        .font(.system(size: iPad ? 20 : 17, weight: .bold, design: .rounded))
                        .foregroundColor(line.isCurrentClass ? TertiaryColor : PrimaryColor)
                    
                    if let end = line.endSec, isToday && line.isCurrentClass {
                        let now = Time.now().seconds
                        let remainingMinutes = max(0, (end - now) / 60)
                        if remainingMinutes > 0 {
                            Text("• \(remainingMinutes)m left")
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.8) : PrimaryColor.opacity(0.6))
                        }
                    }
                }
                
                if !line.teacher.isEmpty || !line.room.isEmpty {
                    HStack(spacing: 8) {
                        if !line.teacher.isEmpty {
                            Text(line.teacher)
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.7))
                        }
                        if !line.room.isEmpty {
                            Text("• \(line.room)")
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.7))
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(iPad ? 16 : 12)
        .background(line.isCurrentClass ? PrimaryColor : SecondaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
