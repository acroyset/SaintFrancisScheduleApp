//
//  DateNavigator.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation
import SwiftUI

struct DateNavigator: View {
    @Binding var showCalendar: Bool
    @Binding var date: Date
    var onPick: (Date) -> Void
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var scheduleDict: [String: [String]]?

    @State private var calendarMonthAnchor: Date = Date() // month shown in the popup

    private let cal = Calendar.current
    private let dfHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, LLLL d, yyyy" // e.g., Wednesday 8-13-25
        return f
    }()
    private let dfMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"  // e.g., August 2025
        return f
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1) The inline header:  < Wed 8-13-25 >
            if (!showCalendar){
                let content = VStack(spacing: 12) {
                    
                    Button {
                        calendarMonthAnchor = startOfMonth(date)
                        withAnimation(.snappy) { showCalendar.toggle() }
                    } label: {
                        Text(dfHeader.string(from: date))
                            .font(.system(
                                size: iPad ? 27 : 20,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .foregroundColor(PrimaryColor)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(12)
                    }
                }
                .padding(.trailing, 12)
                
                if iPad {
                    content.frame(alignment: .leading)
                } else {
                    content.frame(maxWidth: .infinity)
                }
            }
            else {
                let content = VStack(spacing: 8) {
                    Button {
                        calendarMonthAnchor = startOfMonth(date)
                        withAnimation(.snappy) { showCalendar.toggle() }
                    } label: {
                        Text(dfHeader.string(from: date))
                            .font(.system(
                                size: iPad ? 27 : 20,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .foregroundColor(PrimaryColor)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(12)
                    }
                    
                    Divider()
                    
                    HStack {
                        Button {
                            calendarMonthAnchor = cal.date(byAdding: .month, value: -1, to: calendarMonthAnchor) ?? calendarMonthAnchor
                        } label: { Image(systemName: "chevron.left") }

                        if iPad {
                            Spacer(minLength: 12)
                        } else {
                            Spacer()
                        }
                        
                        Text(dfMonth.string(from: calendarMonthAnchor))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(PrimaryColor)
                        
                        if iPad {
                            Spacer(minLength: 12)
                        } else {
                            Spacer()
                        }

                        Button {
                            calendarMonthAnchor = cal.date(byAdding: .month, value: 1, to: calendarMonthAnchor) ?? calendarMonthAnchor
                        } label: { Image(systemName: "chevron.right") }
                    }
                    .padding(8)
                    .padding(.horizontal, 12)

                    let symbols = cal.shortWeekdaySymbols
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(symbols, id: \.self) { s in
                            Text(s.uppercased())
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(PrimaryColor)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)

                    CalendarGrid(month: calendarMonthAnchor,
                         selected: date,
                         PrimaryColor: PrimaryColor,
                         SecondaryColor: SecondaryColor,
                         TertiaryColor: TertiaryColor,
                         onPick: { picked in
                            date = picked
                            withAnimation(.snappy) {
                                onPick(picked)
                            }
                         },
                         scheduleDict: scheduleDict)
                }
                .padding(.bottom, 8)
                .padding(.trailing, 12)
                .transition(.opacity)
                
                if iPad{
                    content.frame(alignment: .leading)
                } else {
                    content
                }
            }
        }
    }

    private func startOfMonth(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }
}
