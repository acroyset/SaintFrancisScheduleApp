//
//  HomeView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct HomeView: View {
    @Binding var selectedDate: Date
    @Binding var showCalendarGrid: Bool
    @Binding var scrollTarget: Int?
    @Binding var addEvent: Bool
    
    let dayCode: String
    let note: String
    let scheduleLines: [ScheduleLine]
    let scheduleDict: [String: [String]]?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    var onDatePick: (Date) -> Void
    
    var body: some View {
        VStack {
            dayHeaderView(
                dayInfo: getDayInfo(for: dayCode),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
            
            DateNavigator(
                showCalendar: $showCalendarGrid,
                date: $selectedDate,
                onPick: onDatePick,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                scheduleDict: scheduleDict
            )
            .padding(.horizontal, 12)
            .zIndex(10)
            
            Divider()
            
            let cal = Calendar.current
            let isToday = cal.isDateInToday(selectedDate)
            
            ClassItemScroll(
                scheduleLines: scheduleLines,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                note: note,
                dayCode: dayCode,
                output: "",
                isToday: isToday,
                iPad: iPad,
                scrollTarget: $scrollTarget,
                addEvent: $addEvent,
                currentDate: selectedDate
            )
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold {
                        withAnimation(.snappy) {
                            let new = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            selectedDate = new
                            onDatePick(new)
                        }
                    } else if value.translation.width < -threshold {
                        withAnimation(.snappy) {
                            let new = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                            selectedDate = new
                            onDatePick(new)
                        }
                    }
                }
        )
    }
    
    private func getDayInfo(for currentDay: String) -> Day? {
        // This would ideally come from a ViewModel
        return nil // Placeholder - implement based on your data structure
    }
}
