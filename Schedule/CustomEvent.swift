//
//  CustomEvent.swift
//  Schedule
//

import Foundation
import SwiftUI
import FirebaseFirestore

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

// MARK: - Simplified Custom Events Manager

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
    
    // MARK: - Cloud Sync (simplified - call from outside)
    
    @MainActor
    func saveToCloud(using authManager: AuthenticationManager) {
        guard let user = authManager.user else { return }
        let userId = user.id
        let eventsToSave = events // Capture events on main actor
        
        Task {
            do {
                try await CloudEventsDataManager().saveEvents(eventsToSave, for: userId)
            } catch {
                print("Failed to save events to cloud: \(error)")
            }
        }
    }
    
    @MainActor
    func loadFromCloud(using authManager: AuthenticationManager) {
        guard let user = authManager.user else { return }
        let userId = user.id
        
        Task {
            do {
                let cloudEvents = try await CloudEventsDataManager().loadEvents(for: userId)
                await MainActor.run {
                    if !cloudEvents.isEmpty {
                        self.events = cloudEvents
                        self.saveEvents() // Save locally as backup
                    }
                }
            } catch {
                print("Failed to load events from cloud: \(error)")
            }
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

// MARK: - Cloud Data Manager for Events

class CloudEventsDataManager {
    private let firestore = Firestore.firestore()
    
    func saveEvents(_ events: [CustomEvent], for userId: String) async throws {
        let eventsData = events.map { event in
            [
                "id": event.id.uuidString,
                "title": event.title,
                "startTime": [
                    "h": event.startTime.h,
                    "m": event.startTime.m,
                    "s": event.startTime.s
                ],
                "endTime": [
                    "h": event.endTime.h,
                    "m": event.endTime.m,
                    "s": event.endTime.s
                ],
                "location": event.location,
                "note": event.note,
                "color": event.color,
                "repeatPattern": event.repeatPattern.rawValue,
                "isEnabled": event.isEnabled,
                "applicableDays": Array(event.applicableDays)
            ] as [String : Any]
        }
        
        try await firestore.collection("users").document(userId).setData([
            "customEvents": eventsData,
            "eventsLastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func loadEvents(for userId: String) async throws -> [CustomEvent] {
        let doc = try await firestore.collection("users").document(userId).getDocument()
        guard let data = doc.data(),
              let eventsArray = data["customEvents"] as? [[String: Any]] else {
            return []
        }
        
        return eventsArray.compactMap { eventDict in
            guard let idString = eventDict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = eventDict["title"] as? String,
                  let startTimeDict = eventDict["startTime"] as? [String: Int],
                  let endTimeDict = eventDict["endTime"] as? [String: Int],
                  let location = eventDict["location"] as? String,
                  let note = eventDict["note"] as? String,
                  let color = eventDict["color"] as? String,
                  let repeatPatternRaw = eventDict["repeatPattern"] as? String,
                  let repeatPattern = RepeatPattern(rawValue: repeatPatternRaw),
                  let isEnabled = eventDict["isEnabled"] as? Bool,
                  let applicableDaysArray = eventDict["applicableDays"] as? [String] else {
                return nil
            }
            
            let startTime = Time(
                h: startTimeDict["h"] ?? 0,
                m: startTimeDict["m"] ?? 0,
                s: startTimeDict["s"] ?? 0
            )
            
            let endTime = Time(
                h: endTimeDict["h"] ?? 0,
                m: endTimeDict["m"] ?? 0,
                s: endTimeDict["s"] ?? 0
            )
            
            var event = CustomEvent(
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: color,
                repeatPattern: repeatPattern,
                applicableDays: Set(applicableDaysArray)
            )
            event.isEnabled = isEnabled
            
            return event
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
