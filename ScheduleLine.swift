//
//  ScheduleLine.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation

struct ScheduleLine: Identifiable, Codable {
    var id = UUID()
    let content: String
    let isCurrentClass: Bool
    let timeRange: String
    let className: String
    let teacher: String
    let room: String

    let startSec: Int?
    let endSec: Int?
    let progress: Double?   // 0...1 for fill amount

    init(content: String,
         isCurrentClass: Bool = false,
         timeRange: String = "",
         className: String = "",
         teacher: String = "",
         room: String = "",
         startSec: Int? = nil,
         endSec: Int? = nil,
         progress: Double? = nil) {
        self.content = content
        self.isCurrentClass = isCurrentClass
        self.timeRange = timeRange
        self.className = className
        self.teacher = teacher
        self.room = room
        self.startSec = startSec
        self.endSec = endSec
        self.progress = progress
    }
}

extension ScheduleLine {
    var durationMinutes: Int {
        guard let start = startSec, let end = endSec else { return 60 } // default fallback
        return max(1, (end - start) / 60) // minimum 1 minute to avoid zero height
    }
    
    var startTime: Time? {
        guard let start = startSec else { return nil }
        return Time(seconds: start)
    }
    
    var endTime: Time? {
        guard let end = endSec else { return nil }
        return Time(seconds: end)
    }
}
