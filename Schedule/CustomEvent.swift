//
//  CustomEvent.swift
//  Schedule
//

import Foundation
import SwiftUI

// MARK: - Custom Event Models

struct CustomEvent: Identifiable, Codable, Equatable {
    let id = UUID()
    var title: String
    var startTime: Time
    var endTime: Time
    var location: String
    var note: String
    var color: String // Hex color
    var repeatPattern: RepeatPattern
    var isEnabled: Bool
    
    // Days this event applies to (for non-repeating events, this is a single day)
    var applicableDays: Set<String> // ["G1", "B1", etc.] or specific dates ["01-15-25"]
    
    init(title: String, startTime: Time, endTime: Time, location: String = "", note: String = "", color: String = "#FF6B6B", repeatPattern: RepeatPattern = .none, applicableDays: Set<String> = []) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.note = note
        self.color = color
        self.repeatPattern = repeatPattern
        self.applicableDays = applicableDays
        self.isEnabled = true
    }
    
    // Check if this event applies to a specific day code
    func appliesTo(dayCode: String, date: Date) -> Bool {
        guard isEnabled else { return false }
        
        switch repeatPattern {
        case .none:
            // Single occurrence - check specific date
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yy"
            let dateString = formatter.string(from: date)
            return applicableDays.contains(dateString)
            
        case .daily:
            // Every school day
            return !dayCode.isEmpty && dayCode != "None"
            
        case .weekly:
            // Same day type every week
            return applicableDays.contains(dayCode)
            
        case .biweekly:
            // Every other week - need to implement week tracking
            return applicableDays.contains(dayCode) // Simplified for now
            
        case .monthly:
            // Same day of month
            let calendar = Calendar.current
            let dayOfMonth = calendar.component(.day, from: date)
            return applicableDays.contains("\(dayOfMonth)")
        }
    }
    
    // Check if this event conflicts with a class
    func conflictsWith(_ scheduleLine: ScheduleLine) -> Bool {
        guard let classStart = scheduleLine.startSec,
              let classEnd = scheduleLine.endSec else { return false }
        
        let eventStart = startTime.seconds
        let eventEnd = endTime.seconds
        
        // Check for time overlap
        return !(eventEnd <= classStart || eventStart >= classEnd)
    }
}

enum RepeatPattern: String, CaseIterable, Codable {
    case none = "None"
    case daily = "Every School Day"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    
    var description: String {
        return self.rawValue
    }
}

// MARK: - Event Conflict Detection

struct EventConflict {
    let event: CustomEvent
    let conflictingScheduleLine: ScheduleLine
    let severity: ConflictSeverity
}

enum ConflictSeverity {
    case minor    // Partial overlap (< 15 minutes)
    case major    // Significant overlap (15+ minutes)
    case complete // Event completely overlaps class
}

// MARK: - Custom Events Manager

class CustomEventsManager: ObservableObject {
    @Published var events: [CustomEvent] = []
    
    private let userDefaults = UserDefaults.standard
    private let eventsKey = "CustomEvents"
    
    init() {
        loadEvents()
    }
    
    // MARK: - Persistence
    
    func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            userDefaults.set(data, forKey: eventsKey)
            
            // Also save to shared group for widget
            SharedGroup.defaults.set(data, forKey: "CustomEvents")
        } catch {
            print("Failed to save custom events: \(error)")
        }
    }
    
    func loadEvents() {
        guard let data = userDefaults.data(forKey: eventsKey) else { return }
        do {
            events = try JSONDecoder().decode([CustomEvent].self, from: data)
        } catch {
            print("Failed to load custom events: \(error)")
        }
    }
    
    // MARK: - Event Management
    
    func addEvent(_ event: CustomEvent) {
        events.append(event)
        saveEvents()
    }
    
    func updateEvent(_ event: CustomEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            saveEvents()
        }
    }
    
    func deleteEvent(_ event: CustomEvent) {
        events.removeAll { $0.id == event.id }
        saveEvents()
    }
    
    func toggleEvent(_ event: CustomEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index].isEnabled.toggle()
            saveEvents()
        }
    }
    
    // MARK: - Event Filtering
    
    func eventsFor(dayCode: String, date: Date) -> [CustomEvent] {
        return events.filter { $0.appliesTo(dayCode: dayCode, date: date) }
    }
    
    // MARK: - Conflict Detection
    
    func detectConflicts(for event: CustomEvent, with scheduleLines: [ScheduleLine]) -> [EventConflict] {
        var conflicts: [EventConflict] = []
        
        for line in scheduleLines {
            if event.conflictsWith(line) {
                let severity = calculateConflictSeverity(event: event, scheduleLine: line)
                conflicts.append(EventConflict(event: event, conflictingScheduleLine: line, severity: severity))
            }
        }
        
        return conflicts
    }
    
    private func calculateConflictSeverity(event: CustomEvent, scheduleLine: ScheduleLine) -> ConflictSeverity {
        guard let classStart = scheduleLine.startSec,
              let classEnd = scheduleLine.endSec else { return .minor }
        
        let eventStart = event.startTime.seconds
        let eventEnd = event.endTime.seconds
        
        let overlapStart = max(eventStart, classStart)
        let overlapEnd = min(eventEnd, classEnd)
        let overlapDuration = overlapEnd - overlapStart
        
        if overlapDuration >= (classEnd - classStart) * 8 / 10 { // 80% or more
            return .complete
        } else if overlapDuration >= 900 { // 15 minutes or more
            return .major
        } else {
            return .minor
        }
    }
}

// MARK: - Extensions

extension Time {
    static func from(hour: Int, minute: Int) -> Time {
        return Time(h: hour, m: minute, s: 0)
    }
}

extension Color {
    static let eventColors: [Color] = [
        Color(hex: "#FF6B6B"), // Red
        Color(hex: "#4ECDC4"), // Teal
        Color(hex: "#45B7D1"), // Blue
        Color(hex: "#96CEB4"), // Green
        Color(hex: "#FFEAA7"), // Yellow
        Color(hex: "#DDA0DD"), // Plum
        Color(hex: "#FFB347"), // Orange
        Color(hex: "#87CEEB")  // Sky Blue
    ]
}
