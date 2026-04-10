//
//  HomeView.swift
//  Schedule
//
//  Uses DirectionalScrollView so horizontal swipes are detected at the
//  UIKit gesture level — the scroll view's pan recognizer is cancelled
//  the instant the direction is clearly horizontal, so it never competes.
//
//  Now includes NowNextCard in the floating header for zero-scan
//  understanding of current class.
//

import SwiftUI

struct HomeView: View {
    private let headerGlassTintOpacity: Double = 0.9

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

    // Header height tracking
    @State private var nowNextHeight: CGFloat = 0
    @State private var dateNavHeight: CGFloat = 0
    @State private var floatingHeaderHeight: CGFloat = 0

    private var headerHeight: CGFloat { floatingHeaderHeight + 16 }
    private var sharedHeaderRadius: CGFloat { max(dateNavHeight / 2, 16) }
    private var nowNextCornerRadius: CGFloat { sharedHeaderRadius + 4 }

    // Swipe state
    @State private var dragX: CGFloat = 0
    @State private var pageID: Date   = Date()
    @State var resetToken = 0

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
        .onChange(of: pageID) {
            resetToken += 1
        }
    }

    // MARK: Page content

    private var pageContent: some View {
        ZStack(alignment: .bottom) {
            DirectionalScrollView(
                topInset: headerHeight,
                bottomInset: iPad ? 160 : 130,
                onHorizontalDrag: handleDrag,
                onHorizontalEnd:  handleDragEnd,
                resetToken: resetToken
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
                            emptyTitle: nextClassEmptyTitle(),
                            emptySubtitle: nextClassEmptySubtitle(),
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

            VStack(spacing: 0) {
                floatingHeader
                Spacer()
            }
            .zIndex(10)
            .simultaneousGesture(headerSwipeGesture)
        }
    }

    // MARK: Drag handlers

    private func handleDrag(_ tx: CGFloat) {
        let limit = screenW * 0.45
        if abs(tx) <= limit {
            dragX = tx
        } else {
            let over = abs(tx) - limit
            dragX = (tx < 0 ? -1 : 1) * (limit + over * 0.10)
        }
    }

    private func handleDragEnd(_ tx: CGFloat, _ vel: CGFloat) {
        let committed = abs(tx) > screenW * 0.28 || abs(vel) > 250
        guard committed else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) { dragX = 0 }
            return
        }

        let goBack = tx > 0
        let exitX: CGFloat = goBack ? screenW : -screenW

        withAnimation(.easeIn(duration: 0.15)) { dragX = exitX }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            let delta   = goBack ? -1 : 1
            let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate

            showCalendarGrid = false
            dragX  = goBack ? -screenW : screenW
            pageID = newDate
            onDatePick(newDate)

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { dragX = 0 }
        }
    }

    // MARK: Scroll mask

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

    private var headerSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                handleDrag(value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                handleDragEnd(value.translation.width, value.predictedEndTranslation.width - value.translation.width)
            }
    }

    @ViewBuilder
    private var floatingHeader: some View {
        trackFloatingHeaderHeight(
            Group {
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    if !isPortrait {
                        HStack(alignment: .top) {
                            VStack(spacing: 6) {
                                headerPill.glassEffect(.regular.tint(PrimaryColor.opacity(headerGlassTintOpacity)))
                                nowNextSection
                            }
                            VStack { dateNav }
                            VStack { addEventInline }
                        }
                    } else {
                        VStack(spacing: 6) {
                            headerPill
                                .frame(maxWidth: .infinity)
                                .glassEffect(.regular.tint(PrimaryColor.opacity(headerGlassTintOpacity)))
                                .padding(.horizontal, 8)
                            nowNextSection
                                .padding(.horizontal, 8)
                            dateNav.padding(.horizontal, 8)
                        }
                    }
                } else {
                    if !isPortrait {
                        HStack(alignment: .top) {
                            VStack(spacing: 6) {
                                headerPill.padding(8).background(PrimaryColor).cornerRadius(16)
                                nowNextSection
                            }
                            VStack { dateNav }
                            VStack { addEventInline }
                        }
                    } else {
                        VStack(spacing: 6) {
                            headerPill
                                .background(PrimaryColor).cornerRadius(16)
                                .frame(maxWidth: .infinity).padding(.horizontal, 8)
                            nowNextSection
                                .padding(.horizontal, 8)
                            dateNav.padding(.horizontal, 8)
                        }
                    }
                }
            }
        )
    }

    // MARK: NOW/NEXT section

    @ViewBuilder
    private var nowNextSection: some View {
        // Only render the card and track its height when it has content
        let showCard = isToday && scheduleDict != nil

        if showCard {
            NowNextCard(
                scheduleLines: scheduleLines,
                dayCode: dayCode,
                note: note,
                isToday: isToday,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                cornerRadius: nowNextCornerRadius,
                usesGlassStyle: false
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { nowNextHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in nowNextHeight = h }
                }
            )
        } else {
            Color.clear.frame(height: 0)
                .onAppear { nowNextHeight = 0 }
        }
    }

    // MARK: Sub-views

    private var headerPill: some View {
        DayHeaderView(
            dayInfo: getDayInfo(for: dayCode),
            dayCode: dayCode,
            isToday: isToday,
            PrimaryColor: PrimaryColor,
            SecondaryColor: SecondaryColor,
            TertiaryColor: TertiaryColor
        )
    }

    private func trackFloatingHeaderHeight<Content: View>(_ content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { floatingHeaderHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in floatingHeaderHeight = h }
            }
        )
    }

    @ViewBuilder
    private var dateNav: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            DateNavigator(
                showCalendar: $showCalendarGrid, date: $selectedDate, onPick: onDatePick,
                PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor, scheduleDict: scheduleDict
            )
            .background(GeometryReader { geo in
                Color.clear.onAppear {
                    if !showCalendarGrid { dateNavHeight = geo.size.height }
                }
                .onChange(of: geo.size.height) { _, h in
                    if !showCalendarGrid { dateNavHeight = h }
                }
            })
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: dateNavHeight / 2))
            .animation(.snappy, value: showCalendarGrid)
            .padding(.horizontal, isPortrait ? 0 : 8)
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
                        .appThemeFont(.primary, size: iPad ? 24 : 20, weight: .semibold)
                    if iPad { Text("Add Personal Event").appThemeFont(.primary, size: 20, weight: .semibold) }
                }
                .foregroundColor(TertiaryColor).padding(12)
            }
            .padding(iPad ? 16 : 8)
            .glassEffect(.regular.tint(PrimaryColor.opacity(headerGlassTintOpacity)))
            .padding(.horizontal, iPad ? 40 : 24)
        } else {
            Button { addEvent = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .appThemeFont(.primary, size: iPad ? 24 : 20, weight: .semibold)
                    if iPad { Text("Add Personal Event").appThemeFont(.primary, size: 20, weight: .semibold) }
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
                        .appThemeFont(.primary, size: iPad ? 24 : 20, weight: .semibold)
                    Text("Add Personal Event")
                        .appThemeFont(.primary, size: iPad ? 20 : 16, weight: .semibold)
                }
                .foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(.vertical, iPad ? 18 : 14)
                .padding(.horizontal, iPad ? 28 : 20)
            }
            .glassEffect(.regular.tint(PrimaryColor.opacity(headerGlassTintOpacity)))
            .padding(.horizontal, iPad ? 40 : 24)
            .padding(.bottom, iPad ? 80 : 70)
            .zIndex(5)
        } else {
            Button { addEvent = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .appThemeFont(.primary, size: iPad ? 24 : 20, weight: .semibold)
                    Text("Add Personal Event")
                        .appThemeFont(.primary, size: iPad ? 20 : 16, weight: .semibold)
                }
                .foregroundColor(TertiaryColor).frame(maxWidth: .infinity)
                .padding(16).background(PrimaryColor).cornerRadius(16).shadow(radius: 8)
            }
            .padding(.horizontal, iPad ? 40 : 24).padding(.bottom, 80).zIndex(5)
        }
    }

    // MARK: Helpers

    func getDayInfo(for currentDay: String) -> Day? {
        guard let di = getDayNumber(for: currentDay),
              let data = data,
              data.days.indices.contains(di) else { return nil }
        return data.days[di]
    }

    func getDayNumber(for currentDay: String) -> Int? {
        ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10][currentDay.lowercased()]
    }

    private func nextClassEmptyTitle() -> String {
        guard scheduleLines.isEmpty else {
            return ""
        }

        guard let nextClassDate = nextClassDate(after: selectedDate) else {
            return "No Classes"
        }

        return "Next class on \(formattedNextClassDate(nextClassDate, relativeTo: selectedDate))"
    }

    private func nextClassEmptySubtitle() -> String? {
        guard scheduleLines.isEmpty,
              let nextClassDate = nextClassDate(after: selectedDate) else {
            return nil
        }

        return formattedNextClassDistance(nextClassDate, relativeTo: selectedDate)
    }

    private func nextClassDate(after date: Date) -> Date? {
        guard let scheduleDict, data != nil else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)

        for offset in 1...60 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = scheduleKey(for: candidate)

            guard let dayCode = scheduleDict[key]?[0],
                  dayHasClasses(dayCode) else {
                continue
            }

            return candidate
        }

        return nil
    }

    private func dayHasClasses(_ dayCode: String) -> Bool {
        guard let day = getDayInfo(for: dayCode) else { return false }
        return !day.names.isEmpty && !day.startTimes.isEmpty
    }

    private func formattedNextClassDate(_ date: Date, relativeTo referenceDate: Date) -> String {
        let calendar = Calendar.current
        let referenceStart = calendar.startOfDay(for: referenceDate)
        let targetStart = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: referenceStart, to: targetStart).day ?? 0

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = dayDistance <= 6 ? "EEEE MMMM d" : "MMMM d"
        return formatter.string(from: date)
    }

    private func formattedNextClassDistance(_ date: Date, relativeTo referenceDate: Date) -> String {
        let calendar = Calendar.current
        let referenceStart = calendar.startOfDay(for: referenceDate)
        let targetStart = calendar.startOfDay(for: date)
        let dayDistance = max(1, calendar.dateComponents([.day], from: referenceStart, to: targetStart).day ?? 1)

        if dayDistance <= 6 {
            return dayDistance == 1 ? "1 day away" : "\(dayDistance) days away"
        }

        if dayDistance <= 10 {
            return "about a week away"
        }

        if dayDistance <= 24 {
            let roundedWeeks = max(1.5, (Double(dayDistance) / 7.0 * 2).rounded() / 2)
            if roundedWeeks == floor(roundedWeeks) {
                return "\(Int(roundedWeeks)) weeks away"
            }
            return "\(roundedWeeks.formatted(.number.precision(.fractionLength(1)))) weeks away"
        }

        if dayDistance <= 34 {
            return "less than a month away"
        }

        if dayDistance <= 44 {
            return "more than a month away"
        }

        let monthsAway = max(2, Int((Double(dayDistance) / 30.0).rounded()))
        return monthsAway == 1 ? "1 month away" : "\(monthsAway) months away"
    }

    private func scheduleKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        return formatter.string(from: date)
    }
}
