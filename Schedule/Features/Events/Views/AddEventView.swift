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
                eventDetailsSection
                timeSection
                colorSection
                dateRepeatSection
                conflictsSection
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
            datePickerSheet
        }
        .onAppear { handleAppear() }
        .onChange(of: title) { _, _ in checkForConflicts() }
        .onChange(of: startTime) { _, _ in checkForConflicts() }
        .onChange(of: endTime) { _, _ in checkForConflicts() }
        .onChange(of: repeatPattern) { _, _ in handleRepeatPatternChanged() }
        .onChange(of: selectedDays) { _, _ in checkForConflicts() }
        .onChange(of: selectedDate) { _, _ in checkForConflicts() }
    }
    
    
    private var eventDetailsSection: some View {
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
    }
    
    private var timeSection: some View {
        Section("Time") {
            DatePicker(
                "Start Time",
                selection: Binding<Date>(
                    get: { startTime.toDate() },
                    set: { startTime = Time.fromDate($0) }
                ),
                displayedComponents: .hourAndMinute
            )

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
    }
    
    private var colorSection: some View {
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
                            .onTapGesture { selectedColor = color }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var dateRepeatSection: some View {
        Section("Date & Repeat") {
            Picker("Repeat Pattern", selection: $repeatPattern) {
                ForEach(RepeatPattern.allCases, id: \.self) { pattern in
                    Text(pattern.description).tag(pattern)
                }
            }
            
            if repeatPattern == .none {
                Button(action: { showingDatePicker = true }) {
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
    }
    
    private var conflictsSection: some View {
        Group {
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
    }
    
    private var datePickerSheet: some View {
        NavigationView {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showingDatePicker = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingDatePicker = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
    
    // ----------------------------------------------------------
    // MARK: - Repeat Options View
    // ----------------------------------------------------------
    
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
            daySelectorGrid(title: "Select which day types:")
        case .biweekly:
            daySelectorGrid(title: "Select which day types (every other week):")
        case .monthly:
            Text("This event will repeat on the same day of each month")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func daySelectorGrid(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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
    }
    
    // ----------------------------------------------------------
    // MARK: - ON APPEAR + LOGIC
    // ----------------------------------------------------------
    
    private func handleAppear() {
        if let event = editingEvent {
            loadEventForEditing(event)
        } else {
            selectedDate = currentDate
            if repeatPattern != .none {
                selectedDays.insert(currentDayCode)
            }
        }
    }
    
    private func handleRepeatPatternChanged() {
        checkForConflicts()
        
        if repeatPattern == .none {
            selectedDays.removeAll()
        } else if selectedDays.isEmpty {
            selectedDays.insert(currentDayCode)
        }
    }
    
    // ----------------------------------------------------------
    // MARK: - Loading / Saving
    // ----------------------------------------------------------
    
    private func loadEventForEditing(_ event: CustomEvent) {
        title = event.title
        startTime = event.startTime
        endTime = event.endTime
        location = event.location
        note = event.note
        selectedColor = Color(hex: event.color)
        repeatPattern = event.repeatPattern
        selectedDays = event.applicableDays
        
        if repeatPattern == .none,
           let dateString = event.applicableDays.first {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            selectedDate = formatter.date(from: dateString) ?? currentDate
        }
    }
    
    private func saveEvent() {
        if let editingEvent = editingEvent {
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
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            return [formatter.string(from: selectedDate)]
        case .daily:
            return []
        case .weekly, .biweekly:
            return selectedDays
        case .monthly:
            let day = Calendar.current.component(.day, from: selectedDate)
            return ["\(day)"]
        }
    }
    
    // ----------------------------------------------------------
    // MARK: - Conflict Detection
    // ----------------------------------------------------------
    
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
        
        var allConflicts = eventsManager.detectConflicts(for: tempEvent, with: scheduleLines)
        let relevantEvents = eventsManager.eventsFor(dayCode: currentDayCode, date: selectedDate)
        
        for otherEvent in relevantEvents {
            if let editingEvent = editingEvent,
               otherEvent.id == editingEvent.id {
                continue
            }
            
            if otherEvent.isEnabled && tempEvent.conflictsWith(otherEvent) {
                let tempLine = ScheduleLine(
                    content: "",
                    base: "",
                    isCurrentClass: false,
                    timeRange: "\(otherEvent.startTime.string()) to \(otherEvent.endTime.string())",
                    className: "📅 \(otherEvent.title)",
                    teacher: otherEvent.location,
                    room: otherEvent.note,
                    startSec: otherEvent.startTime.seconds,
                    endSec: otherEvent.endTime.seconds
                )
                
                let severity = calculateEventConflictSeverity(event1: tempEvent, event2: otherEvent)
                allConflicts.append(
                    EventConflict(event: tempEvent, conflictingScheduleLine: tempLine, severity: severity)
                )
            }
        }
        
        conflicts = allConflicts
    }
    
    private func calculateEventConflictSeverity(event1: CustomEvent, event2: CustomEvent) -> ConflictSeverity {
        let s1 = event1.startTime.seconds
        let e1 = event1.endTime.seconds
        let s2 = event2.startTime.seconds
        let e2 = event2.endTime.seconds
        
        let overlapStart = max(s1, s2)
        let overlapEnd = min(e1, e2)
        let overlap = overlapEnd - overlapStart
        
        let d1 = e1 - s1
        let d2 = e2 - s2
        let minDuration = min(d1, d2)
        
        if overlap >= minDuration * 8 / 10 {
            return .complete
        } else if overlap >= 900 {
            return .major
        } else {
            return .minor
        }
    }
}
