//
//  CalendarGrid.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import SwiftUI

struct CalendarGrid: View {
    let month: Date
    let selected: Date
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var onPick: (Date) -> Void

    private let cal = Calendar.current

    var body: some View {
        let days = makeDays()
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(days, id: \.self) { day in
                if let day = day {
                    let isSelected = cal.isDate(day, inSameDayAs: selected)
                    let isToday = cal.isDateInToday(day)

                    Button {
                        onPick(day)
                    } label: {
                        Text("\(cal.component(.day, from: day))")
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .font(.system(
                                size: iPad ? 20 : 15,
                                weight: .medium,
                                design: .rounded))
                            .foregroundStyle(isSelected ? TertiaryColor : .primary)
                            .background(
                                Group {
                                    if isSelected {
                                        Circle().fill(PrimaryColor)
                                    } else if isToday {
                                        Circle().fill(SecondaryColor)
                                    } else {
                                        Circle().fill(Color.clear)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    // empty leading/trailing cell
                    Color.clear
                        .frame(height: 34)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private func makeDays() -> [Date?] {
        guard
            let range = cal.range(of: .day, in: .month, for: month),
            let first = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }

        let firstWeekdayIndex = (cal.component(.weekday, from: first) + 6) % 7 // 0=Mon if you prefer, adjust as needed
        let daysCount = range.count

        var grid: [Date?] = Array(repeating: nil, count: firstWeekdayIndex)
        for day in 0..<daysCount {
            grid.append(cal.date(byAdding: .day, value: day, to: first)!)
        }

        // pad to full weeks (optional)
        while grid.count % 7 != 0 { grid.append(nil) }
        return grid
    }
}
