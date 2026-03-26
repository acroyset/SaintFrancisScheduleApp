//
//  CalendarGrid.swift
//  Schedule
//
//  Visual hierarchy:
//  • Selected         → filled PrimaryColor circle, TertiaryColor bold text
//  • Today (unselected) → SecondaryColor fill + PrimaryColor ring, PrimaryColor bold text
//  • Normal day (has schedule) → clear background, regular weight text
//  • No schedule day  → clear background, PrimaryColor at 0.25 opacity (clearly dimmed)
//

import SwiftUI

struct CalendarGrid: View {
    let month: Date
    let selected: Date
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var onPick: (Date) -> Void
    var scheduleDict: [String: [String]]? = nil

    private let cal = Calendar.current

    var body: some View {
        let days = makeDays()
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(days.indices, id: \.self) { i in
                if let day = days[i] {
                    let isSelected  = cal.isDate(day, inSameDayAs: selected)
                    let isToday     = cal.isDateInToday(day)
                    let hasSchedule = checkIfSchedule(day)

                    Button {
                        onPick(day)
                    } label: {
                        Text("\(cal.component(.day, from: day))")
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .font(.system(
                                size: iPad ? 20 : 15,
                                weight: (isSelected || isToday) ? .bold : .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(
                                isSelected  ? TertiaryColor :
                                !hasSchedule ? PrimaryColor.opacity(0.25) :
                                               PrimaryColor
                            )
                            .background(
                                ZStack {
                                    if isSelected {
                                        // Filled circle — strongest indicator
                                        Circle().fill(PrimaryColor)
                                    } else if isToday {
                                        // Soft fill + bold ring — clearly "today" without selection
                                        Circle().fill(SecondaryColor)
                                        Circle().strokeBorder(PrimaryColor, lineWidth: 2)
                                    }
                                    // No-schedule and normal days share a clear background;
                                    // they're distinguished purely by text opacity above.
                                }
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
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

        let firstWeekdayIndex = (cal.component(.weekday, from: first) + 6) % 7
        let daysCount = range.count

        var grid: [Date?] = Array(repeating: nil, count: firstWeekdayIndex)
        for day in 0..<daysCount {
            grid.append(cal.date(byAdding: .day, value: day, to: first)!)
        }

        while grid.count % 7 != 0 { grid.append(nil) }
        return grid
    }

    private func checkIfSchedule(_ date: Date) -> Bool {
        let key = getKeyToday(date)
        return scheduleDict?[key] != nil
    }

    private func getKeyToday(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.timeZone = .current
        f.dateFormat = "MM-dd-yy"
        return f.string(from: date)
    }
}
