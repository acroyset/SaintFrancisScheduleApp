//
//  ScheduleListView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct ScheduleListView: View {
    let scheduleLines: [ScheduleLine]
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let note: String
    let dayCode: String
    let output: String
    let isToday: Bool
    let iPad: Bool
    
    @EnvironmentObject var eventsManager: CustomEventsManager
    
    @Binding var scrollTarget: Int?
    @Binding var addEvent: Bool
    
    @State private var showingAddEvent = false
    @State private var editingEvent: CustomEvent?
    
    let currentDate: Date
    
    var body: some View {
        VStack {
            if output.isEmpty && !scheduleLines.isEmpty {
                let combinedItems = createCombinedScheduleItems()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(combinedItems.enumerated()), id: \.offset) { index, item in
                                scheduleItemView(item: item, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
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
                    if output.isEmpty {
                        Text("No classes scheduled")
                            .font(.title2)
                            .foregroundColor(PrimaryColor)
                    } else {
                        Text(output)
                            .font(.title2)
                            .foregroundColor(PrimaryColor)
                    }
                    Spacer()
                }
            }
            
            Button(action: {
                showingAddEvent = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Personal Event")
                }
                .font(.system(size: iPad ? 20 : 16, weight: .semibold))
                .foregroundColor(TertiaryColor)
                .padding()
                .frame(maxWidth: .infinity)
                .background(PrimaryColor)
                .cornerRadius(12)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
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
        .onChange(of: addEvent) { _, shouldAdd in
            if shouldAdd {
                showingAddEvent = true
                addEvent = false
            }
        }
    }
    
    private func createCombinedScheduleItems() -> [ScheduleDisplayItem] {
        var items: [ScheduleDisplayItem] = []
        
        for line in scheduleLines {
            items.append(ScheduleDisplayItem.scheduleLine(line))
        }
        
        let todaysEvents = eventsManager.eventsFor(dayCode: dayCode, date: currentDate)
        for event in todaysEvents {
            items.append(ScheduleDisplayItem.customEvent(event))
        }
        
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
                        .font(.system(size: iPad ? 16 : 14, weight: .medium, design: .monospaced))
                        .foregroundColor(line.isCurrentClass ? TertiaryColor : PrimaryColor.opacity(0.8))
                }
                
                HStack(spacing: 8) {
                    let name = line.className == "Activity" ? note : line.className
                    Text(name.isEmpty ? "Unknown" : name)
                        .font(.system(size: iPad ? 20 : 17, weight: .bold, design: .rounded))
                        .foregroundColor(line.isCurrentClass ? TertiaryColor : PrimaryColor)
                    
                    if let end = line.endSec, isToday && line.isCurrentClass {
                        let now = Time.now().seconds
                        let remainingMinutes = max(0, (end - now) / 60)
                        if remainingMinutes > 0 {
                            Text("• \(remainingMinutes)m left")
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.8) : PrimaryColor.opacity(0.6))
                        }
                    }
                }
                
                if !line.teacher.isEmpty || !line.room.isEmpty {
                    HStack(spacing: 8) {
                        if !line.teacher.isEmpty {
                            Text(line.teacher)
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(line.isCurrentClass ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.7))
                        }
                        if !line.room.isEmpty {
                            Text("• \(line.room)")
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
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
        let now = Time.now().seconds
        let isCurrentEvent = isToday && now >= event.startTime.seconds && now < event.endTime.seconds
        let p = progressValue(start: event.startTime.seconds, end: event.endTime.seconds, now: now)
        
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
                HStack {
                    Text("\(event.startTime.string()) to \(event.endTime.string())")
                        .font(.system(size: iPad ? 16 : 14, weight: .medium, design: .monospaced))
                        .foregroundColor(isCurrentEvent ? TertiaryColor : eventColor.opacity(0.8))
                }
                
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.system(size: iPad ? 20 : 17, weight: .bold, design: .rounded))
                        .foregroundColor(isCurrentEvent ? TertiaryColor : eventColor)
                    
                    if isCurrentEvent {
                        let remainingMinutes = max(0, (event.endTime.seconds - now) / 60)
                        if remainingMinutes > 0 {
                            Text("• \(remainingMinutes)m left")
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(TertiaryColor.opacity(0.8))
                        }
                    }
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isCurrentEvent ? TertiaryColor : eventColor)
                }
                
                if !event.location.isEmpty || !event.note.isEmpty {
                    HStack(spacing: 8) {
                        if !event.location.isEmpty {
                            Text(event.location)
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(isCurrentEvent ? TertiaryColor.opacity(0.9) : eventColor.opacity(0.7))
                        }
                        if !event.note.isEmpty {
                            Text("• \(event.note)")
                                .font(.system(size: iPad ? 16 : 14, weight: .medium))
                                .foregroundColor(isCurrentEvent ? TertiaryColor.opacity(0.9) : eventColor.opacity(0.7))
                        }
                    }
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: {
                    editingEvent = event
                }) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(action: {
                    eventsManager.toggleEvent(event)
                }) {
                    Label(event.isEnabled ? "Disable" : "Enable",
                          systemImage: event.isEnabled ? "pause.circle" : "play.circle")
                }
                
                Button(role: .destructive, action: {
                    eventsManager.deleteEvent(event)
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(isCurrentEvent ? TertiaryColor.opacity(0.7) : eventColor.opacity(0.5))
            }
        }
        .padding(iPad ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrentEvent ? eventColor : SecondaryColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(eventColor, lineWidth: iPad ? 6 : 4)
                )
        )
        .opacity(event.isEnabled ? 1.0 : 0.6)
    }
}

enum ScheduleDisplayItem {
    case scheduleLine(ScheduleLine)
    case customEvent(CustomEvent)
    
    var startTimeSeconds: Int {
        switch self {
        case .scheduleLine(let line):
            return line.startSec ?? Int.max
        case .customEvent(let event):
            return event.startTime.seconds
        }
    }
}
