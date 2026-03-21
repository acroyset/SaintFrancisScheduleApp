//
//  HomeView.swift
//  Schedule
//
//  Shows skeleton cards while schedule is loading, jump-to-today pill,
//  and share via long-press context menu on day name.
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
    let scheduleDict: [String: [String]]?   // nil while still loading
    let data: ScheduleData?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    var isPortrait: Bool
    var onDatePick: (Date) -> Void

    // MARK: - Helpers

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var headerHeight: CGFloat {
        iPad ? isPortrait ? 185 : 130 : isPortrait ? 135 : 100
    }

    private var isLoading: Bool {
        scheduleDict == nil
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Scrollable content ──────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)

                    if isLoading {
                        // Show skeleton while CSV is fetching
                        SkeletonScheduleView(
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor
                        )
                        .padding(.top, 8)
                    } else {
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

                    Color.clear.frame(height: iPad ? 160 : 130)
                }
            }
            .mask(scrollMask)

            // ── Floating header ─────────────────────────────────────────
            VStack(spacing: 0) {
                floatingHeader
                Spacer()
            }
            .zIndex(10)

            // ── Add Event FAB (portrait, only when loaded) ──────────────
            if isPortrait && !isLoading {
                addEventButton
            }
        }
        .gesture(daySwipeGesture)
    }

    // MARK: - Swipe

    private var daySwipeGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                guard abs(value.translation.width) > 50 else { return }
                let delta = value.translation.width > 0 ? -1 : 1
                withAnimation(.snappy) {
                    let new = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
                    onDatePick(new)
                }
            }
    }

    // MARK: - Scroll mask

    @ViewBuilder
    private var scrollMask: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            LinearGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.1),
                .init(color: .black, location: 0.875),
                .init(color: .clear, location: 1.0)
            ]), startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.15),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.875),
                .init(color: .clear, location: 1.0)
            ]), startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Floating header

    @ViewBuilder
    private var floatingHeader: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            floatingHeaderiOS26
        } else {
            floatingHeaderLegacy
        }
    }

    @ViewBuilder
    private var floatingHeaderiOS26: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            if !isPortrait {
                HStack {
                    VStack { dayHeaderRow.glassEffect(.regular.tint(PrimaryColor.opacity(0.9))); Spacer() }
                    VStack { dateNavigatorBlock; Spacer() }
                    VStack { addEventInlineButton; Spacer() }
                }
            } else {
                VStack(spacing: 0) {
                    dayHeaderRow
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular.tint(PrimaryColor.opacity(0.9)))
                        .padding(8)
                    dateNavigatorBlock.padding(.horizontal, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var floatingHeaderLegacy: some View {
        if !isPortrait {
            HStack {
                VStack { dayHeaderRow.padding(8).background(SecondaryColor).cornerRadius(16); Spacer() }
                VStack { dateNavigatorBlock; Spacer() }
                VStack { addEventInlineButton; Spacer() }
            }
        } else {
            VStack(spacing: 0) {
                dayHeaderRow
                    .background(SecondaryColor)
                    .cornerRadius(16)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                dateNavigatorBlock.padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Day header row

    private var dayHeaderRow: some View {
        HStack(spacing: 8) {
            DayHeaderView(
                dayInfo: getDayInfo(for: dayCode),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
    }

    // MARK: - Date navigator

    @ViewBuilder
    private var dateNavigatorBlock: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            if showCalendarGrid {
                DateNavigator(showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                              PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                              TertiaryColor: TertiaryColor, scheduleDict: scheduleDict)
                    .background(TertiaryColor.opacity(0.95)).cornerRadius(32)
                    .padding(.horizontal, isPortrait ? 0 : 8)
                    .animation(.snappy, value: showCalendarGrid).shadow(radius: 16)
            } else {
                DateNavigator(showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                              PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                              TertiaryColor: TertiaryColor, scheduleDict: scheduleDict)
                    .glassEffect()
                    .padding(.horizontal, isPortrait ? 0 : 8)
                    .animation(.snappy, value: showCalendarGrid)
            }
        } else {
            DateNavigator(showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                          PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                          TertiaryColor: TertiaryColor, scheduleDict: scheduleDict)
                .padding(8).background(TertiaryColor).cornerRadius(16)
                .padding(.horizontal, isPortrait ? 0 : 8)
                .animation(.snappy, value: showCalendarGrid).shadow(radius: 16)
        }
    }

    // MARK: - Add event (landscape inline)

    @ViewBuilder
    private var addEventInlineButton: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { addEvent = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    if iPad { Text("Add Personal Event").font(.system(size: iPad ? 20 : 16, weight: .semibold)) }
                }
                .foregroundColor(TertiaryColor).padding(12)
            }
            .padding(iPad ? 16 : 8)
            .glassEffect(.regular.tint(PrimaryColor.opacity(0.9)))
            .padding(.horizontal, iPad ? 40 : 24)
        } else {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { addEvent = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    if iPad { Text("Add Personal Event").font(.system(size: iPad ? 20 : 16, weight: .semibold)) }
                }
                .padding(8).foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(16).background(PrimaryColor).cornerRadius(16).shadow(radius: 8)
            }
            .padding(.horizontal, iPad ? 40 : 24).padding(.bottom, 80)
        }
    }

    // MARK: - Add event FAB (portrait)

    @ViewBuilder
    private var addEventButton: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { addEvent = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    Text("Add Personal Event").font(.system(size: iPad ? 20 : 16, weight: .semibold))
                }
                .foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(.vertical, iPad ? 18 : 14).padding(.horizontal, iPad ? 28 : 20)
            }
            .glassEffect(.regular.tint(PrimaryColor.opacity(0.9)))
            .padding(.horizontal, iPad ? 40 : 24).padding(.bottom, iPad ? 80 : 70).zIndex(5)
        } else {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { addEvent = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    Text("Add Personal Event").font(.system(size: iPad ? 20 : 16, weight: .semibold))
                }
                .foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(16).background(PrimaryColor).cornerRadius(16).shadow(radius: 8)
            }
            .padding(.horizontal, iPad ? 40 : 24).padding(.bottom, 80).zIndex(5)
        }
    }

    // MARK: - Helpers

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
