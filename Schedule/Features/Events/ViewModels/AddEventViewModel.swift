//
//  AddEventViewModel.swift
//  Schedule
//
//  Extracted from AddEventView.swift
//

import Foundation
import SwiftUI

@MainActor
class AddEventViewModel: ObservableObject {
    @Published var title = ""
    @Published var startTime = Time(h: 12, m: 0, s: 0)
    @Published var endTime = Time(h: 13, m: 0, s: 0)
    @Published var location = ""
    @Published var note = ""
    @Published var selectedColor = Color.eventColors.first!
    @Published var repeatPattern = RepeatPattern.none
    @Published var selectedDays: Set<String> = []
    @Published var showingConflicts = false
    @Published var conflicts: [EventConflict] = []
    @Published var selectedDate = Date()
    @Published var showingDatePicker = false
    
    private let eventsManager: CustomEventsManager
    @Published var editingEvent: CustomEvent?
    private let currentDayCode: String
    private let currentDate: Date
    private let scheduleLines: [ScheduleLine]
    
    init(
        eventsManager: CustomEventsManager,
        editingEvent: CustomEvent?,
        currentDayCode: String,
        currentDate: Date,
        scheduleLines: [ScheduleLine]
    ) {
        self.eventsManager = eventsManager
        self.editingEvent = editingEvent
        self.currentDayCode = currentDayCode
        self.currentDate = currentDate
        self.scheduleLines = scheduleLines
    }
    
    // MARK: - Initialization
    
    func loadEventForEditing() {
        guard let event = editingEvent else {
            selectedDate = currentDate
            if repeatPattern != .none {
                selectedDays.insert(currentDayCode)
            }
            return
        }
        
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
    
    // MARK: - Validation
    
    var isValid: Bool {
        return !title.isEmpty && endTime > startTime
    }
    
    // MARK: - Save Event
    
    func saveEvent(completion: @escaping () -> Void) {
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
        
        completion()
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
    
    // MARK: - Conflict Detection
    
    func checkForConflicts() {
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
        let relevantEvents = eventsManager.eventsFor(dayCode: currentDayCode, date: currentDate)
        
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
    
    // MARK: - Repeat Pattern Handling
    
    func handleRepeatPatternChanged() {
        checkForConflicts()
        
        if repeatPattern == .none {
            selectedDays.removeAll()
        } else if selectedDays.isEmpty {
            selectedDays.insert(currentDayCode)
        }
    }
}
