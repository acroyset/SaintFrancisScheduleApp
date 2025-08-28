//
//  ViewBuilders.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation
import SwiftUI

@ViewBuilder
func dayHeaderView(for currentDay: String, getDayInfo: (String) -> Day?, PrimaryColor: Color, SecondaryColor: Color, TertiaryColor: Color) -> some View {
    if let dayInfo = getDayInfo(currentDay) {
        VStack(spacing: 0) {
            Text(dayInfo.name)
                .font(.system(
                    size: iPad ? 60 : 35,
                    weight: .bold))  // fixed
                .foregroundColor(PrimaryColor)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(SecondaryColor)
                .cornerRadius(8)
        }
        .padding(.horizontal)
    } else {
        VStack(spacing: 0) {
            Text(" ")
                .font(.system(
                    size: iPad ? 60 : 35,
                    weight: .bold))  // fixed
                .foregroundColor(PrimaryColor)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(SecondaryColor)
                .cornerRadius(8)
        }
        .padding(.horizontal)
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
                        size: iPad ? 20 : 14,
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
                            size: iPad ? 25 : 17,
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
                                    size: iPad ? 19 : 15,
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
            
            if (!line.teacher.isEmpty && iPad) {
                Text("\(line.teacher)  ")
                    .font(.system(
                        size: iPad ? 20 : 14,
                        weight: line.isCurrentClass ? .bold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(
                        line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
            }
            
            if !line.room.isEmpty {
                Text(line.room)
                    .font(.system(
                        size: iPad ? 20 : 14,
                        weight: line.isCurrentClass ? .bold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(
                        line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
            }
        } else {
            Text(line.content)
                .font(.system(
                    size: iPad ? 23 : 16,
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
