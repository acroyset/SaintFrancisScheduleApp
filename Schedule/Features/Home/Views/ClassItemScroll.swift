//
//  Enhanced ClassItemScroll with Custom Events and Edit Support
//  Schedule
//

import SwiftUI

struct ClassItemScroll: View {
    let scheduleLines: [ScheduleLine]
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let note: String
    let dayCode: String
    let emptyTitle: String
    let emptySubtitle: String?
    let isToday: Bool
    let iPad: Bool
    
    @EnvironmentObject var eventsManager: CustomEventsManager
    
    @Binding var scrollTarget: Int?
    @Binding var addEvent: Bool
    @Binding var addReminder: Bool
    
    // Custom events integration
    @State private var showingAddEvent = false
    @State private var showingAddReminder = false
    @State private var editingEvent: CustomEvent?
    @State private var editingReminder: CustomEvent?
    @State private var showingConflictAlert = false
    @State private var conflictingEvents: [CustomEvent] = []
    
    let currentDate: Date
    
    init(scheduleLines: [ScheduleLine], PrimaryColor: Color, SecondaryColor: Color, TertiaryColor: Color, note: String, dayCode: String, emptyTitle: String, emptySubtitle: String?, isToday: Bool, iPad: Bool, scrollTarget: Binding<Int?>, addEvent: Binding<Bool>, addReminder: Binding<Bool>, currentDate: Date = Date()) {
        self.scheduleLines = scheduleLines
        self.PrimaryColor = PrimaryColor
        self.SecondaryColor = SecondaryColor
        self.TertiaryColor = TertiaryColor
        self.note = note
        self.dayCode = dayCode
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.isToday = isToday
        self.iPad = iPad
        self._scrollTarget = scrollTarget
        self._addEvent = addEvent
        self._addReminder = addReminder
        self.currentDate = currentDate
    }
    
    var body: some View {
        VStack {
            let combinedItems = createCombinedScheduleItems()
            
            if !combinedItems.isEmpty {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 12) {
                        ForEach(Array(combinedItems.enumerated()), id: \.offset) { index, item in
                            scheduleItemView(item: item, index: index)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .onChange(of: scrollTarget) { _, target in
                        if let target = target {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text(emptyTitle)
                            .appThemeFont(.primary, size: iPad ? 32 : 24, weight: .bold)
                            .foregroundColor(PrimaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let emptySubtitle, !emptySubtitle.isEmpty {
                            Text(emptySubtitle)
                                .appThemeFont(.secondary, size: iPad ? 18 : 14, weight: .medium)
                                .foregroundColor(PrimaryColor.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    Spacer()
                }
            }
            
            // Add Event Button
            
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventView(
                isPresented: $showingAddEvent,
                editingEvent: nil,
                eventsManager: eventsManager,
                currentDayCode: dayCode,
                currentDate: currentDate,
                scheduleLines: scheduleLines,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(isPresented: $showingAddReminder) {
            AddReminderView(
                isPresented: $showingAddReminder,
                editingReminder: nil,
                eventsManager: eventsManager,
                currentDate: currentDate,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(item: $editingEvent) { event in
            AddEventView(
                isPresented: Binding(
                    get: { editingEvent != nil },
                    set: { if !$0 { editingEvent = nil } }
                ),
                editingEvent: event,
                eventsManager: eventsManager,
                currentDayCode: dayCode,
                currentDate: currentDate,
                scheduleLines: scheduleLines,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(item: $editingReminder) { reminder in
            AddReminderView(
                isPresented: Binding(
                    get: { editingReminder != nil },
                    set: { if !$0 { editingReminder = nil } }
                ),
                editingReminder: reminder,
                eventsManager: eventsManager,
                currentDate: currentDate,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .onChange(of: addEvent) { _, shouldAdd in
            if shouldAdd {
                showingAddEvent = true
                addEvent = false
            }
        }
        .onChange(of: addReminder) { _, shouldAdd in
            if shouldAdd {
                showingAddReminder = true
                addReminder = false
            }
        }
        .onAppear {
            checkAllConflicts()
        }
        .onChange(of: eventsManager.events) { _, _ in
            checkAllConflicts()
        }
    }
    
    private func createCombinedScheduleItems() -> [ScheduleDisplayItem] {
        var items: [ScheduleDisplayItem] = []
        
        // Add regular schedule lines
        for line in scheduleLines {
            items.append(ScheduleDisplayItem.scheduleLine(line))
        }
        
        // Add custom events for this day
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: currentDate)
        for event in todaysEvents {
            items.append(ScheduleDisplayItem.customEvent(event))
        }
        
        // Sort by start time
        items.sort { first, second in
            let firstTime = first.startTimeSeconds
            let secondTime = second.startTimeSeconds
            return firstTime < secondTime
        }
        
        return items
    }
    
    @ViewBuilder
    private func scheduleItemView(item: ScheduleDisplayItem, index: Int) -> some View {
        switch item {
        case .scheduleLine(let line):
            classRowView(line: line)
            
        case .customEvent(let event):
            customEventRowView(event: event)
        }
    }
    
    @ViewBuilder
    private func classRowView(line: ScheduleLine) -> some View {
        HStack(spacing: 12) {
            if let progress = line.progress {
                ClassProgressBar(
                    progress: progress,
                    active: line.isCurrentClass,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .frame(width: 6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if !line.timeRange.isEmpty {
                    Text(line.timeRange)
                        .appThemeFont(.secondary, size: iPad ? 16 : 14, weight: .medium)
                        .foregroundColor(line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                }
                
                HStack(spacing: 8) {
                    let name = line.className == "Activity" ? note : line.className
                    Text(name.isEmpty ? "Unknown" : name)
                        .appThemeFont(.primary, size: iPad ? 20 : 17, weight: .bold)
                        .foregroundColor(line.isCurrentClass ? TertiaryColor : PrimaryColor)
                    
                    if let end = line.endSec, isToday && line.isCurrentClass {
                        let now = Time.now().seconds
                        let remainingSeconds = max(0, (end - now))
                        if remainingSeconds > 60 {
                            let remainingMinutes = floor(Double(remainingSeconds)/60.0)
                            Text("• \(Int(remainingMinutes))m left")
                                .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                .foregroundColor(TertiaryColor.opacity(0.8))
                        } else if (remainingSeconds > 0){
                            Text("• \(Int(remainingSeconds))s left")
                                .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                .foregroundColor(TertiaryColor.opacity(0.8))
                        }
                    }
                }
                
                if !line.teacher.isEmpty || !line.room.isEmpty {
                    HStack(spacing: 8) {
                        if !line.teacher.isEmpty {
                            Text(line.teacher)
                                .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.7))
                        }
                        if !line.room.isEmpty {
                            Text("• \(line.room)")
                                .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.7))
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(iPad ? 16 : 12)
        .background(line.isCurrentClass ? PrimaryColor : SecondaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    @ViewBuilder
    private func customEventRowView(event: CustomEvent) -> some View {
        let eventColor = Color(hex: event.color)
        if event.isReminder {
            reminderRowView(event: event, eventColor: eventColor)
        } else {
            let now = Time.now().seconds
            let isCurrentEvent = isToday && now >= event.startTime.seconds && now < event.endTime.seconds

            let p = progressValue(start: event.startTime.seconds, end: event.endTime.seconds, now: now)

            // Check for conflicts with this event
            let eventConflicts = getEventConflicts(for: event)
            let hasConflicts = !eventConflicts.isEmpty

            HStack(spacing: 12) {
                ClassProgressBar(
                    progress: p,
                    active: isCurrentEvent,
                    PrimaryColor: eventColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .frame(width: 6)

                VStack(alignment: .leading, spacing: 4) {
                    itemTypeBadge(title: "EVENT", systemImage: "calendar", tint: eventColor)

                    HStack {
                        Text("\(event.startTime.string()) to \(event.endTime.string())")
                            .appThemeFont(.secondary, size: iPad ? 16 : 14, weight: .medium)
                            .foregroundColor(eventColor.opacity(0.8))

                        if hasConflicts {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(event.title)
                            .appThemeFont(.primary, size: iPad ? 20 : 17, weight: .bold)
                            .foregroundColor(eventColor)

                        if isCurrentEvent {
                            let remainingSeconds = max(0, (event.endTime.seconds - now))
                            if remainingSeconds > 60 {
                                let remainingMinutes = floor(Double(remainingSeconds) / 60.0)
                                Text("• \(Int(remainingMinutes))m left")
                                    .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                    .foregroundColor(eventColor.opacity(0.8))
                            } else if remainingSeconds > 0 {
                                Text("• \(Int(remainingSeconds))s left")
                                    .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                    .foregroundColor(eventColor.opacity(0.8))
                            }
                        }

                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(eventColor)
                    }

                    if !event.location.isEmpty || !event.note.isEmpty {
                        HStack(spacing: 8) {
                            if !event.location.isEmpty {
                                Text(event.location)
                                    .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                    .foregroundColor(PrimaryColor.opacity(0.72))
                            }
                            if !event.note.isEmpty {
                                Text("• \(event.note)")
                                    .appThemeFont(.primary, size: iPad ? 16 : 14, weight: .medium)
                                    .foregroundColor(PrimaryColor.opacity(0.72))
                            }
                        }
                    }

                    if event.repeatPattern != .none {
                        Text(event.repeatPattern.description)
                            .appThemeFont(.primary, size: iPad ? 14 : 12, weight: .medium)
                            .foregroundColor(eventColor.opacity(0.65))
                    }

                    if hasConflicts {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10))
                            Text("\(eventConflicts.count) conflict(s)")
                                .appThemeFont(.secondary, size: 10)
                        }
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                Menu {
                    Button(action: {
                        editingEvent = event
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: {
                        eventsManager.deleteEvent(event)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(eventColor.opacity(0.55))
                }
            }
            .padding(iPad ? 16 : 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(eventColor.opacity(isCurrentEvent ? 0.18 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(eventColor.opacity(isCurrentEvent ? 0.45 : 0.24), lineWidth: iPad ? 5 : 3)
                    )
            )
        }
    }

    @ViewBuilder
    private func reminderRowView(event: CustomEvent, eventColor: Color) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(eventColor)
                    .frame(width: 12, height: 12)

                Rectangle()
                    .fill(eventColor.opacity(0.45))
                    .frame(width: 2)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(event.startTime.string())
                        .appThemeFont(.secondary, size: iPad ? 15 : 13, weight: .bold)
                        .foregroundColor(eventColor)

                    Text("Reminder")
                        .appThemeFont(.secondary, size: iPad ? 13 : 11, weight: .bold)
                        .foregroundColor(eventColor.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(eventColor.opacity(0.12))
                        .clipShape(Capsule())

                    if !event.reminderSummary.isEmpty {
                        Text(event.reminderSummary)
                            .appThemeFont(.secondary, size: iPad ? 13 : 11, weight: .medium)
                            .foregroundColor(eventColor.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Text(event.title)
                    .appThemeFont(.primary, size: iPad ? 18 : 15, weight: .semibold)
                    .foregroundColor(eventColor)

                if !event.note.isEmpty {
                    Text(event.note)
                        .appThemeFont(.secondary, size: iPad ? 14 : 12, weight: .medium)
                        .foregroundColor(eventColor.opacity(0.6))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button(action: {
                    editingReminder = event
                }) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive, action: {
                    eventsManager.deleteEvent(event)
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appThemeFont(.primary, size: iPad ? 18 : 16, weight: .semibold)
                    .foregroundColor(eventColor.opacity(0.45))
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, iPad ? 16 : 12)
        .padding(.vertical, iPad ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(eventColor.opacity(0.10))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(eventColor.opacity(0.24), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func itemTypeBadge(title: String, systemImage: String, tint: Color? = nil) -> some View {
        let badgeTint = tint ?? PrimaryColor

        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .appThemeFont(.secondary, size: iPad ? 11 : 10, weight: .bold)
        }
        .foregroundColor(badgeTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeTint.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private func getEventConflicts(for event: CustomEvent) -> [EventConflict] {
        guard !event.isReminder else { return [] }
        var conflicts: [EventConflict] = []
        
        // Check conflicts with schedule lines
        let scheduleConflicts = eventsManager.detectConflicts(for: event, with: scheduleLines)
        conflicts.append(contentsOf: scheduleConflicts)
        
        // Check conflicts with other events
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: currentDate)
        for otherEvent in todaysEvents {
            if otherEvent.id != event.id && event.conflictsWith(otherEvent) {
                // Create a temporary ScheduleLine to represent the other event for conflict detection
                let tempLine = ScheduleLine(
                    content: "",
                    base: "",
                    isCurrentClass: false,
                    timeRange: "\(otherEvent.startTime.string()) to \(otherEvent.endTime.string())",
                    className: otherEvent.title,
                    teacher: otherEvent.location,
                    room: otherEvent.note,
                    startSec: otherEvent.startTime.seconds,
                    endSec: otherEvent.endTime.seconds
                )
                
                let severity = calculateEventConflictSeverity(event1: event, event2: otherEvent)
                conflicts.append(EventConflict(event: event, conflictingScheduleLine: tempLine, severity: severity))
            }
        }
        
        return conflicts
    }
    
    private func calculateEventConflictSeverity(event1: CustomEvent, event2: CustomEvent) -> ConflictSeverity {
        let event1Start = event1.startTime.seconds
        let event1End = event1.endTime.seconds
        let event2Start = event2.startTime.seconds
        let event2End = event2.endTime.seconds
        
        let overlapStart = max(event1Start, event2Start)
        let overlapEnd = min(event1End, event2End)
        let overlapDuration = overlapEnd - overlapStart
        
        let event1Duration = event1End - event1Start
        let event2Duration = event2End - event2Start
        let minDuration = min(event1Duration, event2Duration)
        
        if overlapDuration >= minDuration * 8 / 10 { // 80% or more overlap
            return .complete
        } else if overlapDuration >= 900 { // 15 minutes or more
            return .major
        } else {
            return .minor
        }
    }
    
    private func checkAllConflicts() {
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: currentDate)
        var hasAnyConflicts = false

        for event in todaysEvents {
            guard !event.isReminder else { continue }
            let conflicts = getEventConflicts(for: event)
            if !conflicts.isEmpty {
                hasAnyConflicts = true
                break
            }
        }
        
        if hasAnyConflicts && !showingConflictAlert {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingConflictAlert = true
            }
        }
    }
}
