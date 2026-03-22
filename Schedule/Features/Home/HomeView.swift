//
//  HomeView.swift
//  Schedule
//
//  Uses DirectionalScrollView so horizontal swipes are detected at the
//  UIKit gesture level — the scroll view's pan recognizer is cancelled
//  the instant the direction is clearly horizontal, so it never competes.
//
//  Result: swiping left/right always works on the first try, even when
//  starting a touch that has any slight vertical component.
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
    var isPortrait: Bool
    var onDatePick: (Date) -> Void

    // MARK: Swipe state
    @State private var dragX: CGFloat = 0
    @State private var pageID: Date   = Date()
    @State private var resetScroll = false

    private var screenW: CGFloat { UIScreen.main.bounds.width }
    private var isToday: Bool    { Calendar.current.isDateInToday(selectedDate) }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            pageContent
                .offset(x: dragX)

            if isPortrait && scheduleDict != nil {
                addEventFAB
            }
        }
        .clipped()
        
        .onChange(of: pageID) { _, _ in
            resetScroll = true
            DispatchQueue.main.async {
                resetScroll = false
            }
        }
    }

    // MARK: Page content

    private var pageContent: some View {
        ZStack(alignment: .bottom) {
            // ── Scrollable list via UIKit wrapper ──────────────────────
            DirectionalScrollView(
                topInset: headerHeight,
                bottomInset: iPad ? 160 : 130,
                onHorizontalDrag: handleDrag,
                onHorizontalEnd:  handleDragEnd,
                resetScroll: resetScroll
            ) {
                VStack(spacing: 0) {
                    
                    if scheduleDict == nil {
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
                        .id(pageID)
                    }
                }
            }
            .mask(scrollMask)

            // ── Header slides WITH the content ─────────────────────────
            VStack(spacing: 0) {
                floatingHeader
                Spacer()
            }
            .zIndex(10)
        }
    }

    // MARK: Drag handlers

    private func handleDrag(_ tx: CGFloat) {
        // 1:1 tracking with a soft rubber-band past 45% screen width
        let limit = screenW * 0.45
        if abs(tx) <= limit {
            dragX = tx
        } else {
            let over = abs(tx) - limit
            dragX = (tx < 0 ? -1 : 1) * (limit + over * 0.10)
        }
    }

    private func handleDragEnd(_ tx: CGFloat, _ vel: CGFloat) {
        // Commit if dragged far enough OR flicked fast enough
        let committed = abs(tx) > screenW * 0.28 || abs(vel) > 250
        guard committed else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) { dragX = 0 }
            return
        }

        let goBack   = tx > 0          // swipe right → go to yesterday
        let exitX: CGFloat = goBack ? screenW : -screenW

        // Fly current page off
        withAnimation(.easeIn(duration: 0.15)) { dragX = exitX }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            let delta   = goBack ? -1 : 1
            let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate

            // Place incoming page on opposite side (no animation) then spring in
            dragX  = goBack ? -screenW : screenW
            pageID = newDate

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                dragX = 0
            }
            onDatePick(newDate)
        }
    }

    // MARK: Layout helpers

    private var headerHeight: CGFloat {
        iPad ? isPortrait ? 185 : 130 : isPortrait ? 135 : 100
    }

    @ViewBuilder
    private var scrollMask: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            LinearGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.875),
                .init(color: .clear, location: 1.0)
            ]), startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.15),
                .init(color: .black, location: 0.20),
                .init(color: .black, location: 0.875),
                .init(color: .clear, location: 1.0)
            ]), startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Floating header

    @ViewBuilder
    private var floatingHeader: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            if !isPortrait {
                HStack {
                    VStack { headerPill.glassEffect(.regular.tint(PrimaryColor.opacity(0.9))); Spacer() }
                    VStack { dateNav; Spacer() }
                    VStack { addEventInline; Spacer() }
                }
            } else {
                VStack(spacing: 0) {
                    headerPill
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular.tint(PrimaryColor.opacity(0.9)))
                        .padding(8)
                    dateNav.padding(.horizontal, 8)
                }
            }
        } else {
            if !isPortrait {
                HStack {
                    VStack { headerPill.padding(8).background(SecondaryColor).cornerRadius(16); Spacer() }
                    VStack { dateNav; Spacer() }
                    VStack { addEventInline; Spacer() }
                }
            } else {
                VStack(spacing: 0) {
                    headerPill
                        .background(SecondaryColor).cornerRadius(16)
                        .frame(maxWidth: .infinity).padding(8)
                    dateNav.padding(.horizontal, 8)
                }
            }
        }
    }

    private var headerPill: some View {
        DayHeaderView(
            dayInfo: getDayInfo(for: dayCode),
            PrimaryColor: PrimaryColor,
            SecondaryColor: SecondaryColor,
            TertiaryColor: TertiaryColor
        )
    }

    @ViewBuilder
    private var dateNav: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            if showCalendarGrid {
                DateNavigator(
                    showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                    PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor, scheduleDict: scheduleDict
                )
                .background(TertiaryColor.opacity(0.95)).cornerRadius(32)
                .padding(.horizontal, isPortrait ? 0 : 8)
                .animation(.snappy, value: showCalendarGrid).shadow(radius: 16)
            } else {
                DateNavigator(
                    showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                    PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor, scheduleDict: scheduleDict
                )
                .glassEffect()
                .padding(.horizontal, isPortrait ? 0 : 8)
                .animation(.snappy, value: showCalendarGrid)
            }
        } else {
            DateNavigator(
                showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor, scheduleDict: scheduleDict
            )
            .padding(8).background(TertiaryColor).cornerRadius(16)
            .padding(.horizontal, isPortrait ? 0 : 8)
            .animation(.snappy, value: showCalendarGrid).shadow(radius: 16)
        }
    }

    @ViewBuilder
    private var addEventInline: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            Button { addEvent = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    if iPad { Text("Add Personal Event")
                        .font(.system(size: 20, weight: .semibold)) }
                }
                .foregroundColor(TertiaryColor).padding(12)
            }
            .padding(iPad ? 16 : 8)
            .glassEffect(.regular.tint(PrimaryColor.opacity(0.9)))
            .padding(.horizontal, iPad ? 40 : 24)
        } else {
            Button { addEvent = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    if iPad { Text("Add Personal Event")
                        .font(.system(size: 20, weight: .semibold)) }
                }
                .padding(8).foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(16).background(PrimaryColor).cornerRadius(16).shadow(radius: 8)
            }
            .padding(.horizontal, iPad ? 40 : 24).padding(.bottom, 80)
        }
    }

    @ViewBuilder
    private var addEventFAB: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            Button { addEvent = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    Text("Add Personal Event")
                        .font(.system(size: iPad ? 20 : 16, weight: .semibold))
                }
                .foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(.vertical, iPad ? 18 : 14)
                .padding(.horizontal, iPad ? 28 : 20)
            }
            .glassEffect(.regular.tint(PrimaryColor.opacity(0.9)))
            .padding(.horizontal, iPad ? 40 : 24)
            .padding(.bottom, iPad ? 80 : 70)
            .zIndex(5)
        } else {
            Button { addEvent = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iPad ? 24 : 20, weight: .semibold))
                    Text("Add Personal Event")
                        .font(.system(size: iPad ? 20 : 16, weight: .semibold))
                }
                .foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(16).background(PrimaryColor).cornerRadius(16).shadow(radius: 8)
            }
            .padding(.horizontal, iPad ? 40 : 24).padding(.bottom, 80).zIndex(5)
        }
    }

    // MARK: Day helpers

    func getDayInfo(for currentDay: String) -> Day? {
        guard let di = getDayNumber(for: currentDay),
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return data.days[di]
    }

    func getDayNumber(for currentDay: String) -> Int? {
        ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10][currentDay.lowercased()]
    }
}

