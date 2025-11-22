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
    
    @State private var scrollOffset: CGFloat = 0
    
    // Calculate dynamic header height
    private var headerHeight: CGFloat {
        showCalendarGrid ? iPad ? 530 : 480 : iPad ? 180 : 140
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main scroll content with mask
            ScrollView {
                VStack(spacing: 0) {
                    // Spacer for header and date picker
                    Color.clear
                        .frame(height: headerHeight)
                    
                    let cal = Calendar.current
                    let isToday = cal.isDateInToday(selectedDate)
                    
                    // Actual content
                    VStack(spacing: 0) {
                        
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
                        
                        // Bottom padding to ensure last item isn't hidden behind button
                        Color.clear.frame(height: iPad ? 160 : 140)
                    }
                }
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .coordinateSpace(name: "scroll")
            
            // Floating header and date picker
            VStack(spacing: 0) {
                if #available(iOS 26.0, *) {
                    DayHeaderView(
                        dayInfo: getDayInfo(for: dayCode),
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .glassEffect(.regular.tint(PrimaryColor.opacity(0.7)))
                    .padding(8)
                    
                    if showCalendarGrid{
                        DateNavigator(
                            showCalendar: $showCalendarGrid,
                            date: $selectedDate,
                            onPick: onDatePick,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            scheduleDict: scheduleDict
                        )
                        .background(.ultraThinMaterial.opacity(0.95))
                        .cornerRadius(32)
                        .padding(8)
                        .animation(.snappy, value: showCalendarGrid)
                    } else {
                        DateNavigator(
                            showCalendar: $showCalendarGrid,
                            date: $selectedDate,
                            onPick: onDatePick,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            scheduleDict: scheduleDict
                        )
                        .glassEffect()
                        .padding(.horizontal, 8)
                        .animation(.snappy, value: showCalendarGrid)
                    }
                } else {
                    DayHeaderView(
                        dayInfo: getDayInfo(for: dayCode),
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .background(.ultraThinMaterial.opacity(0.95))
                    .cornerRadius(8)
                    .padding(8)
                    
                    DateNavigator(
                        showCalendar: $showCalendarGrid,
                        date: $selectedDate,
                        onPick: onDatePick,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        scheduleDict: scheduleDict
                    )
                    .background(.ultraThinMaterial.opacity(0.95))
                    .cornerRadius(16)
                    .padding(8)
                    .animation(.snappy, value: showCalendarGrid)
                }
                
                Spacer()
            }
            .zIndex(10)
            
            // Add Personal Event button
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
                .padding(.bottom, iPad ? 80 : 70)
                .zIndex(5)
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
                    .background(.ultraThinMaterial.opacity(0.95))
                    .cornerRadius(16)
                    .shadow(radius: 8)
                }
                .padding(.horizontal, iPad ? 40 : 24)
                .padding(.bottom, 70)
                .zIndex(5)
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
