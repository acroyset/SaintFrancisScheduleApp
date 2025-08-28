//
//  Structs.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

struct ScheduleData {
    var classes: [ClassItem]
    var days: [Day]
}

struct ClassItem: Equatable {
    var name: String
    var teacher: String
    var room: String
    
    static func == (a: ClassItem, b: ClassItem) -> Bool {
        return (a.name == b.name && a.room == b.room && a.teacher == b.teacher)
    }
}

struct Day {
    var name = ""
    var names: [String] = []
    var startTimes: [Time] = []
    var endTimes: [Time] = []
    var note = ""
}
