//
//  HomeworkItem.swift
//  Schedule
//

import Foundation

enum HomeworkPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "arrow.down.circle.fill"
        case .normal: return "circle.fill"
        case .high: return "exclamationmark.circle.fill"
        }
    }

    var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

enum HomeworkReminderChoice: String, Codable, CaseIterable, Identifiable {
    case none
    case nightBefore
    case morningOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No Reminder"
        case .nightBefore: return "Night Before"
        case .morningOf: return "Morning Of"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "Just keep it in the app"
        case .nightBefore: return "7:00 PM the day before"
        case .morningOf: return "7:00 AM on the due date"
        }
    }
}

struct HomeworkItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var className: String
    var title: String
    var details: String
    var dueDate: Date
    var priority: HomeworkPriority
    var reminderChoice: HomeworkReminderChoice
    var isComplete: Bool
    var createdAt: Date
    var completedAt: Date?

    var isOverdue: Bool {
        !isComplete && Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date())
    }
}
