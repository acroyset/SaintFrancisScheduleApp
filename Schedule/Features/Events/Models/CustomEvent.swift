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
