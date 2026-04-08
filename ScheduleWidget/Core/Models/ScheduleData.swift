//
//  ScheduleData.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation

struct ScheduleData: Codable {
    var classes: [ClassItem]
    var days: [Day]
    var isSecondLunch: [Bool] = [false, false]

    static let defaultClasses: [ClassItem] = [
        ClassItem(name: "Period 1", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Period 2", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Period 3", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Period 4", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Period 5", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Period 6", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Period 7", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Lunch", teacher: "N", room: "N"),
        ClassItem(name: "Student Collaboration", teacher: "N", room: "N"),
        ClassItem(name: "Advisory", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Break", teacher: "N", room: "N"),
        ClassItem(name: "Faculty Collaboration", teacher: "N", room: "N"),
        ClassItem(name: "Homeroom", teacher: "Teacher", room: "Room"),
        ClassItem(name: "Activity", teacher: "N", room: "N"),
        ClassItem(name: "Brunch", teacher: "N", room: "N"),
        ClassItem(name: "Liturgy", teacher: "N", room: "Gym")
    ]

    func normalized() -> ScheduleData {
        var copy = self
        if copy.isSecondLunch.count < 2 {
            copy.isSecondLunch += Array(repeating: false, count: 2 - copy.isSecondLunch.count)
        } else if copy.isSecondLunch.count > 2 {
            copy.isSecondLunch = Array(copy.isSecondLunch.prefix(2))
        }

        if copy.classes.count < Self.defaultClasses.count {
            copy.classes += Self.defaultClasses.dropFirst(copy.classes.count)
        }

        return copy
    }
}
