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
                VStack(spacing: 12) {
                    
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
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }

            // 2) Calendar popup overlay (dismiss on outside tap)
            else {
                // full-screen invisible layer to dismiss
                //Color.black.opacity(0.1)
                //    .ignoresSafeArea()
                //    .onTapGesture { withAnimation(.snappy) { showCalendar = false } }

                // the popup panel (anchored under the header)
                VStack(spacing: 8) {
                    // month header with arrows
                    HStack {
                        Button {
                            // Swipe right - go to previous day
                            calendarMonthAnchor = cal.date(byAdding: .month, value: -1, to: calendarMonthAnchor) ?? calendarMonthAnchor
                        } label: { Image(systemName: "chevron.left") }

                        Spacer()
                        Text(dfMonth.string(from: calendarMonthAnchor))
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()

                        Button {
                            calendarMonthAnchor = cal.date(byAdding: .month, value: 1, to: calendarMonthAnchor) ?? calendarMonthAnchor
                        } label: { Image(systemName: "chevron.right") }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    // weekday headers
                    let symbols = cal.shortWeekdaySymbols // Sun Mon Tue ...
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(symbols, id: \.self) { s in
                            Text(s.uppercased())
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)

                    // days grid
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
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(radius: 8, y: 4)
                )
                .padding(.top, 36)         // drop just below header
                .padding(.trailing, 12)    // keep inside screen edge
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private func startOfMonth(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }
}
