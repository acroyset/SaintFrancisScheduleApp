//
//  AddEventView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation
import SwiftUI

struct AddEventView: View {
    @StateObject private var eventsManager = CustomEventsManager()
    @Binding var isPresented: Bool
    
    var editingEvent: CustomEvent?
    var currentDayCode: String
    var currentDate: Date
    var scheduleLines: [ScheduleLine]
    
    @State private var title = ""
    @State private var startTime = Time(h: 12, m: 0, s: 0)
    @State private var endTime = Time(h: 13, m: 0, s: 0)
    @State private var location = ""
    @State private var note = ""
    @State private var selectedColor = Color.eventColors.first!
    @State private var repeatPattern = RepeatPattern.none
    @State private var selectedDays: Set<String> = []
    @State private var showingConflicts = false
    @State private var conflicts: [EventConflict] = []
    
    // Date selection for single events
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    let dayTypes = ["G1", "B1", "G2", "B2", "A1", "A2", "A3", "A4", "L1", "L2", "S1"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event Title", text: $title)
                    
                    HStack {
                        Text("Location")
                        Spacer()
                        TextField("Optional", text: $location)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Notes")
                        Spacer()
                        TextField("Optional", text: $note)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Time") {
                    DatePicker("Start Time", selection: Binding(
                        get: { startTime.toDate() },
                        set: { startTime = Time.fromDate($0) }
                    ), displayedComponents: .hourAndMinute)
                    
                    DatePicker("End Time", selection: Binding(
                        get: { endTime.toDate() },
                        set: { endTime = Time.fromDate($0) }
                    ), displayedComponents: .hourAndMinute)
                    
                    if endTime <= startTime {
                        Text("End time must be after start time")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Color.eventColors, id: \.description) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(PrimaryColor, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Section("Date & Repeat") {
                    Picker("Repeat Pattern", selection: $repeatPattern) {
                        ForEach(RepeatPattern.allCases, id: \.self) { pattern in
                            Text(pattern.description).tag(pattern)
                        }
                    }
                    
                    if repeatPattern == .none {
                        // Show date picker for single events
                        Button(action: {
                            showingDatePicker = true
                        }) {
                            HStack {
                                Text("Event Date")
                                    .foregroundColor(PrimaryColor)
                                Spacer()
                                Text(DateFormatter.eventDate.string(from: selectedDate))
                                    .foregroundColor(PrimaryColor.opacity(0.7))
                                Image(systemName: "chevron.right")
                                    .foregroundColor(PrimaryColor.opacity(0.5))
                            }
                        }
                    } else {
                        repeatOptionsView
                    }
                }
                
                if !conflicts.isEmpty {
                    Section(header:
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Schedule Conflicts")
                        }
                    ) {
                        ForEach(conflicts.indices, id: \.self) { index in
                            ConflictRowView(conflict: conflicts[index])
                        }
                    }
                }
            }
            .navigationTitle(editingEvent == nil ? "Add Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(title.isEmpty || endTime <= startTime)
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingDatePicker = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if let event = editingEvent {
                loadEventForEditing(event)
            } else {
                // Set default values for new event
                selectedDate = currentDate
                if repeatPattern != .none {
                    selectedDays.insert(currentDayCode)
                }
            }
        }
        .onChange(of: title) { _, _ in checkForConflicts() }
        .onChange(of: startTime) { _, _ in checkForConflicts() }
        .onChange(of: endTime) { _, _ in checkForConflicts() }
        .onChange(of: repeatPattern) { _, _ in
            checkForConflicts()
            // Clear selected days when changing repeat pattern
            if repeatPattern == .none {
                selectedDays.removeAll()
            } else if selectedDays.isEmpty {
                selectedDays.insert(currentDayCode)
            }
        }
        .onChange(of: selectedDays) { _, _ in checkForConflicts() }
        .onChange(of: selectedDate) { _, _ in checkForConflicts() }
    }
    
    @ViewBuilder
    private var repeatOptionsView: some View {
        switch repeatPattern {
        case .none:
            EmptyView()
            
        case .daily:
            Text("This event will appear every school day")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .weekly:
            VStack(alignment: .leading, spacing: 8) {
                Text("Select which day types:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(Array(dayTypes.enumerated()), id: \.offset) { _, dayType in
                        Button(dayType) {
                            if selectedDays.contains(dayType) {
                                selectedDays.remove(dayType)
                            } else {
                                selectedDays.insert(dayType)
                            }
                        }
                        .padding(8)
                        .background(selectedDays.contains(dayType) ? PrimaryColor : SecondaryColor)
                        .foregroundColor(selectedDays.contains(dayType) ? TertiaryColor : PrimaryColor)
                        .cornerRadius(8)
                    }
                }
            }
            
        case .biweekly:
            VStack(alignment: .leading, spacing: 8) {
                Text("Select which day types (every other week):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(dayTypes, id: \.self) { dayType in
                        Button(dayType) {
                            if selectedDays.contains(dayType) {
                                selectedDays.remove(dayType)
                            } else {
                                selectedDays.insert(dayType)
                            }
                        }
                        .padding(8)
                        .background(selectedDays.contains(dayType) ? PrimaryColor : SecondaryColor)
                        .foregroundColor(selectedDays.contains(dayType) ? TertiaryColor : PrimaryColor)
                        .cornerRadius(8)
                    }
                }
            }
            
        case .monthly:
            Text("This event will repeat on the same day of each month")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func loadEventForEditing(_ event: CustomEvent) {
        title = event.title
        startTime = event.startTime
        endTime = event.endTime
        location = event.location
        note = event.note
        selectedColor = Color(hex: event.color)
        repeatPattern = event.repeatPattern
        selectedDays = event.applicableDays
        
        // For single events, try to parse the date from applicableDays
        if repeatPattern == .none, let dateString = event.applicableDays.first {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            selectedDate = formatter.date(from: dateString) ?? currentDate
        }
    }
    
    private func saveEvent() {
        if let editingEvent = editingEvent {
            // For editing, preserve the original ID and enabled state
            let updatedEvent = CustomEvent(
                id: editingEvent.id,
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: selectedColor.toHex() ?? "#FF6B6B",
                repeatPattern: repeatPattern,
                applicableDays: getApplicableDays(),
                isEnabled: editingEvent.isEnabled
            )
            eventsManager.updateEvent(updatedEvent)
        } else {
            // For new events, create with new ID
            let newEvent = CustomEvent(
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: selectedColor.toHex() ?? "#FF6B6B",
                repeatPattern: repeatPattern,
                applicableDays: getApplicableDays()
            )
            eventsManager.addEvent(newEvent)
        }
        
        isPresented = false
    }
    
    private func getApplicableDays() -> Set<String> {
        switch repeatPattern {
        case .none:
            // Single occurrence on selected date
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            return [formatter.string(from: selectedDate)]
            
        case .daily:
            return [] // Empty set means all school days
            
        case .weekly, .biweekly:
            return selectedDays
            
        case .monthly:
            let dayOfMonth = Calendar.current.component(.day, from: selectedDate)
            return ["\(dayOfMonth)"]
        }
    }
    
    private func checkForConflicts() {
        guard !title.isEmpty && endTime > startTime else {
            conflicts = []
            return
        }
        
        let tempEvent = CustomEvent(
            title: title,
            startTime: startTime,
            endTime: endTime,
            location: location,
            note: note,
            color: selectedColor.toHex() ?? "#FF6B6B",
            repeatPattern: repeatPattern,
            applicableDays: getApplicableDays()
        )
        
        // Check conflicts with schedule lines
        var allConflicts = eventsManager.detectConflicts(for: tempEvent, with: scheduleLines)
        
        // Check conflicts with other custom events
        let relevantEvents = eventsManager.eventsFor(dayCode: currentDayCode, date: selectedDate)
        for otherEvent in relevantEvents {
            // Skip if it's the same event we're editing
            if let editingEvent = editingEvent, otherEvent.id == editingEvent.id {
                continue
            }
            
            if otherEvent.isEnabled && tempEvent.conflictsWith(otherEvent) {
                // Create a temporary ScheduleLine to represent the other event
                let tempLine = ScheduleLine(
                    content: "",
                    base: "",
                    isCurrentClass: false,
                    timeRange: "\(otherEvent.startTime.string()) to \(otherEvent.endTime.string())",
                    className: "📅 \(otherEvent.title)", // Add emoji to distinguish from class conflicts
                    teacher: otherEvent.location,
                    room: otherEvent.note,
                    startSec: otherEvent.startTime.seconds,
                    endSec: otherEvent.endTime.seconds
                )
                
                let severity = calculateEventConflictSeverity(event1: tempEvent, event2: otherEvent)
                allConflicts.append(EventConflict(event: tempEvent, conflictingScheduleLine: tempLine, severity: severity))
            }
        }
        
        conflicts = allConflicts
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
}
