//
//  CustomEvent.swift (Fixed with proper ID handling)
//  Schedule
//

import Foundation
import SwiftUI

// MARK: - Custom Event Models

import FirebaseFirestore

enum CustomItemKind: String, CaseIterable, Codable {
    case event
    case reminder
}

enum ReminderOffset: String, CaseIterable, Codable, Identifiable {
    case atTime
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case oneDay

    var id: String { rawValue }

    var secondsBefore: Int {
        switch self {
        case .atTime:
            return 0
        case .tenMinutes:
            return 10 * 60
        case .thirtyMinutes:
            return 30 * 60
        case .oneHour:
            return 60 * 60
        case .twoHours:
            return 2 * 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .atTime:
            return "At time"
        case .tenMinutes:
            return "10 min before"
        case .thirtyMinutes:
            return "30 min before"
        case .oneHour:
            return "1 hour before"
        case .twoHours:
            return "2 hours before"
        case .oneDay:
            return "Day before"
        }
    }

    var shortLabel: String {
        switch self {
        case .atTime:
            return "At time"
        case .tenMinutes:
            return "10 min"
        case .thirtyMinutes:
            return "30 min"
        case .oneHour:
            return "1 hr"
        case .twoHours:
            return "2 hr"
        case .oneDay:
            return "Day before"
        }
    }
}

struct CustomEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var startTime: Time
    var endTime: Time
    var location: String
    var note: String
    var color: String // Hex color
    var repeatPattern: RepeatPattern
    var kind: CustomItemKind
    var reminderOffsets: [ReminderOffset]
    
    // Days this event applies to (for non-repeating events, this is a single day)
    var applicableDays: Set<String> // ["G1", "B1", etc.] or specific dates ["01-15-25"]
    
    init(title: String, startTime: Time, endTime: Time, location: String = "", note: String = "", color: String = "#FF6B6B", repeatPattern: RepeatPattern = .none, kind: CustomItemKind = .event, reminderOffsets: [ReminderOffset] = [], applicableDays: Set<String> = []) {
        self.id = UUID()
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.note = note
        self.color = color
        self.repeatPattern = repeatPattern
        self.kind = kind
        self.reminderOffsets = reminderOffsets
        self.applicableDays = applicableDays
    }
    
    // Custom initializer for editing with preserved ID
    init(id: UUID, title: String, startTime: Time, endTime: Time, location: String = "", note: String = "", color: String = "#FF6B6B", repeatPattern: RepeatPattern = .none, kind: CustomItemKind = .event, reminderOffsets: [ReminderOffset] = [], applicableDays: Set<String> = []) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.note = note
        self.color = color
        self.repeatPattern = repeatPattern
        self.kind = kind
        self.reminderOffsets = reminderOffsets
        self.applicableDays = applicableDays
    }

    var isReminder: Bool {
        kind == .reminder
    }

    var reminderSummary: String {
        let labels = reminderOffsets
            .sorted { $0.secondsBefore > $1.secondsBefore }
            .map(\.shortLabel)

        return labels.joined(separator: " • ")
    }

    var firstApplicableDate: Date? {
        guard repeatPattern == .none,
              let dateString = applicableDays.first else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        return formatter.date(from: dateString)
    }

    var reminderEndDate: Date? {
        guard isReminder,
              let reminderDate = firstApplicableDate else { return nil }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = startTime.h
        components.minute = startTime.m
        components.second = startTime.s
        return Calendar.current.date(from: components)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startTime
        case endTime
        case location
        case note
        case color
        case repeatPattern
        case kind
        case reminderOffsets
        case applicableDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startTime = try container.decode(Time.self, forKey: .startTime)
        endTime = try container.decode(Time.self, forKey: .endTime)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#FF6B6B"
        repeatPattern = try container.decodeIfPresent(RepeatPattern.self, forKey: .repeatPattern) ?? .none
        kind = try container.decodeIfPresent(CustomItemKind.self, forKey: .kind) ?? .event
        reminderOffsets = try container.decodeIfPresent([ReminderOffset].self, forKey: .reminderOffsets) ?? []
        applicableDays = try container.decodeIfPresent(Set<String>.self, forKey: .applicableDays) ?? []
    }
    
    // Check if this event applies to a specific day code
    func appliesTo(dayCode: String, date: Date) -> Bool {
        
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
        guard !isReminder else { return false }
        guard let classStart = scheduleLine.startSec,
              let classEnd = scheduleLine.endSec else { return false }
        
        let eventStart = startTime.seconds
        let eventEnd = endTime.seconds
        
        // Check for time overlap
        return !(eventEnd <= classStart || eventStart >= classEnd)
    }
    
    // Check if this event conflicts with another event
    func conflictsWith(_ other: CustomEvent) -> Bool {
        guard !isReminder, !other.isReminder else { return false }
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
