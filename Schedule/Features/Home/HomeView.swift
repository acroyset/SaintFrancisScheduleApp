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
    let data: ScheduleData?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    var onDatePick: (Date) -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                DayHeaderView(
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
                    .padding(.vertical, 8)
                
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
            
            if #available(iOS 26.0, *) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        addEvent = true
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: iPad ? 24 : 20, weight: .semibold))
                        Text("Add Personal Event")
                            .font(.system(size: iPad ? 20 : 16, weight: .semibold))
                    }
                    .foregroundColor(PrimaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, iPad ? 18 : 14)
                    .padding(.horizontal, iPad ? 28 : 20)
                    .glassEffect()
                }
                .padding(.horizontal, iPad ? 40 : 24)
                .padding(.bottom, 70)
                .zIndex(50)
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        addEvent = true
                    }
                }) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    Text("Add Personal Event")
                        .font(.system(size: iPad ? 20 : 16, weight: .semibold))
                }
                .foregroundColor(PrimaryColor)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(TertiaryColor)
                .cornerRadius(16)
                .shadow(radius: 8)
                .padding(16)
                .padding(.bottom, 70)
                }
            }
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
    
    func getDayInfo(for currentDay: String) -> Day? {
        guard let di = getDayNumber(for: currentDay),
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return data.days[di]
    }
    
    func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        return map[currentDay.lowercased()]
    }
}
