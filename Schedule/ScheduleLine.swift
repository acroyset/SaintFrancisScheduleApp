//
//  ScheduleLine.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation

struct ScheduleLine: Identifiable {
    let id = UUID()
    let content: String
    let isCurrentClass: Bool
    let timeRange: String
    let className: String
    let teacher: String
    let room: String

    // NEW
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
