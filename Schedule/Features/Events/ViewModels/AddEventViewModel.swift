//
//  AddEventViewModel.swift  (crash fix)
//  Schedule
//
//  Fixes:
//  1. Trailing comma in CustomEvent initializer (runtime crash)
//  2. completion() called before async updateEvent/addEvent finishes
//  3. updateEvent dispatches to barrier queue — sheet was dismissing
//     before the write completed, causing a use-after-free on the view
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

    // MARK: - Save Event (FIXED)
    //
    // Previously: completion() was called unconditionally at the end of the
    // function, which dismissed the sheet before the async barrier write on
    // eventsManager finished — causing a crash.
    //
    // Fix: call completion() only after the synchronous part is done, and
    // keep the async cloud-save happening in the background independently.
    // The CustomEventsManager methods (addEvent/updateEvent) are already
    // fire-and-forget from the caller's perspective; the crash was caused by
    // the sheet teardown racing the barrier queue write.

    func saveEvent(completion: @escaping () -> Void) {
        let applicableDays = getApplicableDays()
        let colorHex = selectedColor.toHex() ?? "#FF6B6BFF"

        if let editingEvent = editingEvent {
            // Build updated event — NO trailing comma (that was also a bug)
            let updatedEvent = CustomEvent(
                id: editingEvent.id,
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: colorHex,
                repeatPattern: repeatPattern,
                applicableDays: applicableDays
            )

            // Perform the update synchronously on the main queue,
            // then dismiss. The internal async cloud-save is independent.
            eventsManager.updateEventSync(updatedEvent)
        } else {
            let newEvent = CustomEvent(
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: colorHex,
                repeatPattern: repeatPattern,
                applicableDays: applicableDays
            )

            eventsManager.addEventSync(newEvent)
        }

        // Dismiss the sheet after the in-memory update is committed.
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
        case .weekly:
            return selectedDays
        case .weekday:
            return selectedDays
        case .biweekly:
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
            color: selectedColor.toHex() ?? "#FF6B6BFF",
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

            if tempEvent.conflictsWith(otherEvent) {
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
                    EventConflict(
                        event: tempEvent,
                        conflictingScheduleLine: tempLine,
                        severity: severity
                    )
                )
            }
        }

        conflicts = allConflicts
    }

    private func calculateEventConflictSeverity(
        event1: CustomEvent,
        event2: CustomEvent
    ) -> ConflictSeverity {
        let s1 = event1.startTime.seconds
        let e1 = event1.endTime.seconds
        let s2 = event2.startTime.seconds
        let e2 = event2.endTime.seconds

        let overlapStart = max(s1, s2)
        let overlapEnd   = min(e1, e2)
        let overlap      = overlapEnd - overlapStart

        let d1 = e1 - s1
        let d2 = e2 - s2
        let minDuration = min(d1, d2)

        if overlap >= minDuration * 8 / 10 { return .complete }
        if overlap >= 900                  { return .major    }
        return .minor
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
