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
    var isCurrentClass: Bool
    var timeRange: String  // Changed from 'let' to 'var'
    let className: String
    let teacher: String
    let room: String

    var startSec: Int?     // Changed from 'let' to 'var'
    var endSec: Int?       // Changed from 'let' to 'var'
    var progress: Double?
    
    let base: String

    init(content: String,
         base: String,
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
        self.base = base
    }
}

