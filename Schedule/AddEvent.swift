//
//  AddEventView.swift
//  Schedule
//

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
    
    // NEW: Date selection for single events
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
        var eventToSave = CustomEvent(
            title: title,
            startTime: startTime,
            endTime: endTime,
            location: location,
            note: note,
            color: selectedColor.toHex() ?? "#FF6B6B",
            repeatPattern: repeatPattern,
            applicableDays: getApplicableDays()
        )
        
        if let editingEvent = editingEvent {
            // Preserve the existing ID for updates
            eventToSave = CustomEvent(
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: selectedColor.toHex() ?? "#FF6B6B",
                repeatPattern: repeatPattern,
                applicableDays: getApplicableDays()
            )
            eventsManager.updateEvent(eventToSave)
        } else {
            eventsManager.addEvent(eventToSave)
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
        
        conflicts = eventsManager.detectConflicts(for: tempEvent, with: scheduleLines)
    }
}

struct ConflictRowView: View {
    let conflict: EventConflict
    
    var body: some View {
        HStack {
            Image(systemName: conflictIcon)
                .foregroundColor(conflictColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.conflictingScheduleLine.className)
                    .font(.headline)
                
                Text(conflict.conflictingScheduleLine.timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(conflictSeverityText)
                .font(.caption)
                .padding(4)
                .background(conflictColor.opacity(0.2))
                .cornerRadius(4)
        }
    }
    
    private var conflictIcon: String {
        switch conflict.severity {
        case .minor: return "exclamationmark.circle"
        case .major: return "exclamationmark.triangle"
        case .complete: return "xmark.circle"
        }
    }
    
    private var conflictColor: Color {
        switch conflict.severity {
        case .minor: return .yellow
        case .major: return .orange
        case .complete: return .red
        }
    }
    
    private var conflictSeverityText: String {
        switch conflict.severity {
        case .minor: return "Minor"
        case .major: return "Major"
        case .complete: return "Complete"
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let eventDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Time Extensions

extension Time {
    func toDate() -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = h
        components.minute = m
        return calendar.date(from: components) ?? Date()
    }
    
    static func fromDate(_ date: Date) -> Time {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Time(h: components.hour ?? 0, m: components.minute ?? 0, s: 0)
    }
}

extension Color {
    func toHex() -> String? {
        let resolved = UIColor(self).resolvedColor(with: UIScreen.main.traitCollection)
        guard let cg = resolved.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ) else { return nil }

        let comps = cg.components ?? []
        let r,g,b,a: CGFloat
        switch comps.count {
        case 2: r = comps[0]; g = comps[0]; b = comps[0]; a = comps[1]       // grayscale
        case 4: r = comps[0]; g = comps[1]; b = comps[2]; a = comps[3]       // rgba
        default: return nil
        }

        let R = Int(round(r*255)), G = Int(round(g*255)), B = Int(round(b*255)), A = Int(round(a*255))
        return String(format:"#%02X%02X%02X%02X", R,G,B,A)
    }
}
