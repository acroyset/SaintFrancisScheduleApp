//
//  CustomEvent.swift (Fixed with proper ID handling)
//  Schedule
//

import Foundation
import SwiftUI

// MARK: - Custom Event Models

import FirebaseFirestore

struct CustomEvent: Identifiable, Codable, Equatable {
    let id: UUID
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
        self.id = UUID()
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
    
    // Custom initializer for editing with preserved ID
    init(id: UUID, title: String, startTime: Time, endTime: Time, location: String = "", note: String = "", color: String = "#FF6B6B", repeatPattern: RepeatPattern = .none, applicableDays: Set<String> = [], isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.note = note
        self.color = color
        self.repeatPattern = repeatPattern
        self.applicableDays = applicableDays
        self.isEnabled = isEnabled
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
            
        case .weekday:
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: date)
            let weekdayString = "\(weekday)" // 1=Sunday, 2=Monday, etc.
            return applicableDays.contains(weekdayString)
            
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
    
    // Check if this event conflicts with another event
    func conflictsWith(_ other: CustomEvent) -> Bool {
        let selfStart = self.startTime.seconds
        let selfEnd = self.endTime.seconds
        let otherStart = other.startTime.seconds
        let otherEnd = other.endTime.seconds
        
        // Check for time overlap
        return !(selfEnd <= otherStart || selfStart >= otherEnd)
    }
    
    // Equatable implementation
    static func == (lhs: CustomEvent, rhs: CustomEvent) -> Bool {
        return lhs.id == rhs.id
    }
}

enum RepeatPattern: String, CaseIterable, Codable {
    case none = "None"
    case daily = "Every School Day"
    case weekly = "Weekly (Day Type)"  // Gold 1, Brown 2, etc.
    case weekday = "Weekly (Weekday)"  // Monday, Friday, etc.
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    
    var description: String {
        return self.rawValue
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
            
            return CustomEvent(
                id: id,
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: color,
                repeatPattern: repeatPattern,
                applicableDays: Set(applicableDaysArray),
                isEnabled: isEnabled
            )
        }
    }
}
