//
//  AddEventView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation
import SwiftUI

struct AddEventView: View {
    @StateObject private var viewModel: AddEventViewModel
    @Binding var isPresented: Bool
    
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    let dayTypes = ["G1", "B1", "G2", "B2", "A1", "A2", "A3", "A4", "L1", "L2", "S1"]
    
    init(
        isPresented: Binding<Bool>,
        editingEvent: CustomEvent? = nil,
        eventsManager: CustomEventsManager,
        currentDayCode: String,
        currentDate: Date,
        scheduleLines: [ScheduleLine],
        PrimaryColor: Color,
        SecondaryColor: Color,
        TertiaryColor: Color
    ) {
        self._isPresented = isPresented
        self.PrimaryColor = PrimaryColor
        self.SecondaryColor = SecondaryColor
        self.TertiaryColor = TertiaryColor
        
        let vm = AddEventViewModel(
            eventsManager: eventsManager,
            editingEvent: editingEvent,
            currentDayCode: currentDayCode,
            currentDate: currentDate,
            scheduleLines: scheduleLines
        )
        _viewModel = StateObject<AddEventViewModel>(wrappedValue: vm)
    }
    
    var body: some View {
        let content: NavigationView = NavigationView {
            Form {
                EventDetailsSection(viewModel: viewModel)
                TimeSection(viewModel: viewModel)
                ColorSection(viewModel: viewModel, PrimaryColor: PrimaryColor)
                DateRepeatSection(viewModel: viewModel, dayTypes: dayTypes, PrimaryColor: PrimaryColor, SecondaryColor: SecondaryColor)
                ConflictsSection(conflicts: viewModel.conflicts)
            }
            .navigationTitle(viewModel.editingEvent == nil ? "Add Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.saveEvent { isPresented = false }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        
        return content
            .sheet(isPresented: $viewModel.showingDatePicker) {
                DatePickerSheet(selectedDate: $viewModel.selectedDate)
            }
            .onAppear { viewModel.loadEventForEditing() }
            .onChange(of: viewModel.startTime) { _, _ in viewModel.checkForConflicts() }
            .onChange(of: viewModel.endTime) { _, _ in viewModel.checkForConflicts() }
            .onChange(of: viewModel.repeatPattern) { _, _ in viewModel.handleRepeatPatternChanged() }
            .onChange(of: viewModel.selectedDays) { _, _ in viewModel.checkForConflicts() }
            .onChange(of: viewModel.selectedDate) { _, _ in viewModel.checkForConflicts() }
    }
}

// MARK: - Event Details Section

private struct EventDetailsSection: View {
    @ObservedObject var viewModel: AddEventViewModel
    
    var body: some View {
        Section("Event Details") {
            TextField("Event Title", text: $viewModel.title)
            
            HStack {
                Text("Location")
                Spacer()
                TextField("Optional", text: $viewModel.location)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Notes")
                Spacer()
                TextField("Optional", text: $viewModel.note)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Time Section

private struct TimeSection: View {
    @ObservedObject var viewModel: AddEventViewModel
    
    var body: some View {
        Section("Time") {
            DatePicker(
                "Start Time",
                selection: Binding<Date>(
                    get: { viewModel.startTime.toDate() },
                    set: { viewModel.startTime = Time.fromDate($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            
            DatePicker(
                "End Time",
                selection: Binding(
                    get: { viewModel.endTime.toDate() },
                    set: { viewModel.endTime = Time.fromDate($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            
            if viewModel.endTime <= viewModel.startTime {
                Text("End time must be after start time")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Color Section

private struct ColorSection: View {
    @ObservedObject var viewModel: AddEventViewModel
    let PrimaryColor: Color
    
    var body: some View {
        Section("Color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Color.eventColors, id: \.description) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(PrimaryColor, lineWidth: viewModel.selectedColor == color ? 3 : 0)
                            )
                            .onTapGesture { viewModel.selectedColor = color }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Date & Repeat Section

private struct DateRepeatSection: View {
    @ObservedObject var viewModel: AddEventViewModel
    let dayTypes: [String]
    let PrimaryColor: Color
    let SecondaryColor: Color
    
    var body: some View {
        Section("Date & Repeat") {
            Picker("Repeat Pattern", selection: $viewModel.repeatPattern) {
                Text("None").tag(RepeatPattern.none)
                Text("Every School Day").tag(RepeatPattern.daily)
                Text("Weekly (Day Type)").tag(RepeatPattern.weekly)
                Text("Weekly (Weekday)").tag(RepeatPattern.weekday)  // ADD THIS
                Text("Biweekly").tag(RepeatPattern.biweekly)
                Text("Monthly").tag(RepeatPattern.monthly)
            }
            
            if viewModel.repeatPattern == .none {
                Button(action: { viewModel.showingDatePicker = true }) {
                    HStack {
                        Text("Event Date")
                            .foregroundColor(PrimaryColor)
                        Spacer()
                        Text(DateFormatter.eventDate.string(from: viewModel.selectedDate))
                            .foregroundColor(PrimaryColor.opacity(0.7))
                        Image(systemName: "chevron.right")
                            .foregroundColor(PrimaryColor.opacity(0.5))
                    }
                }
            } else {
                RepeatOptionsView(
                    viewModel: viewModel,
                    dayTypes: dayTypes,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor
                )
            }
        }
    }
}

// MARK: - Repeat Options View

private struct RepeatOptionsView: View {
    @ObservedObject var viewModel: AddEventViewModel
    let dayTypes: [String]
    let PrimaryColor: Color
    let SecondaryColor: Color
    
    let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    var body: some View {
        switch viewModel.repeatPattern {
        case .none:
            EmptyView()
        case .daily:
            Text("This event will appear every school day")
                .font(.caption)
                .foregroundColor(.secondary)
        case .weekly:
            DaySelectorGrid(
                selectedDays: $viewModel.selectedDays,
                dayTypes: dayTypes,
                title: "Select which day types:",
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor
            )
        case .weekday:
            WeekdaySelectorGrid(
                selectedDays: $viewModel.selectedDays,
                weekdays: weekdays,
                title: "Select which weekdays:",
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor
            )
        case .biweekly:
            DaySelectorGrid(
                selectedDays: $viewModel.selectedDays,
                dayTypes: dayTypes,
                title: "Select which day types (every other week):",
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor
            )
        case .monthly:
            Text("This event will repeat on the same day of each month")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Day Selector Grid

private struct DaySelectorGrid: View {
    @Binding var selectedDays: Set<String>
    let dayTypes: [String]
    let title: String
    let PrimaryColor: Color
    let SecondaryColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(dayTypes, id: \.self) { dayType in
                    Button(action:{
                        if selectedDays.contains(dayType) {
                            selectedDays.remove(dayType)
                        } else {
                            selectedDays.insert(dayType)
                        }
                    }) {
                        Text(dayType)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(selectedDays.contains(dayType) ? PrimaryColor : SecondaryColor)
                            .foregroundColor(selectedDays.contains(dayType) ? .white : PrimaryColor)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Weekday Selector Grid

private struct WeekdaySelectorGrid: View {
    @Binding var selectedDays: Set<String>
    let weekdays: [String]
    let title: String
    let PrimaryColor: Color
    let SecondaryColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(weekdays.indices, id: \.self) { index in
                    let weekday = weekdays[index]
                    let weekdayValue = "\(index + 1)" // 1=Sunday, 2=Monday, etc.
                    
                    WeekdayButton(
                        weekday: weekday,
                        weekdayValue: weekdayValue,
                        isSelected: selectedDays.contains(weekdayValue),
                        onToggle: {
                            if selectedDays.contains(weekdayValue) {
                                selectedDays.remove(weekdayValue)
                            } else {
                                selectedDays.insert(weekdayValue)
                            }
                        },
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor
                    )
                }
            }
        }
    }
}

// MARK: - Weekday Button Component

private struct WeekdayButton: View {
    let weekday: String
    let weekdayValue: String
    let isSelected: Bool
    let onToggle: () -> Void
    let PrimaryColor: Color
    let SecondaryColor: Color
    
    var body: some View {
        Text(weekday)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? PrimaryColor : SecondaryColor)
            .foregroundColor(isSelected ? .white : PrimaryColor)
            .cornerRadius(8)
            .onTapGesture {
                onToggle()
            }
    }
}

// MARK: - Conflicts Section

private struct ConflictsSection: View {
    let conflicts: [EventConflict]
    
    var body: some View {
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

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

