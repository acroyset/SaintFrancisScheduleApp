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
        ClassItem(id: defaultClassID(1), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(2), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(3), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(4), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(5), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(6), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(7), name: "", teacher: "", room: ""),
        ClassItem(id: defaultClassID(8), name: "Lunch", teacher: "N", room: "N"),
        ClassItem(id: defaultClassID(9), name: "Student Collaboration", teacher: "N", room: "N"),
        ClassItem(id: defaultClassID(10), name: "Advisory", teacher: "", room: ""),
        ClassItem(id: defaultClassID(11), name: "Break", teacher: "N", room: "N"),
        ClassItem(id: defaultClassID(12), name: "Faculty Collaboration", teacher: "N", room: "N"),
        ClassItem(id: defaultClassID(13), name: "Homeroom", teacher: "", room: ""),
        ClassItem(id: defaultClassID(14), name: "Activity", teacher: "N", room: "N"),
        ClassItem(id: defaultClassID(15), name: "Brunch", teacher: "N", room: "N"),
        ClassItem(id: defaultClassID(16), name: "Liturgy", teacher: "N", room: "Gym")
    ]

    private static func defaultClassID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

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

        for index in copy.classes.indices {
            let trimmedName = copy.classes[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTeacher = copy.classes[index].teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedRoom = copy.classes[index].room.trimmingCharacters(in: .whitespacesAndNewlines)

            if index < 7, trimmedName.caseInsensitiveCompare("Period \(index + 1)") == .orderedSame {
                copy.classes[index].name = ""
            }
            if ["teacher", "teahcer"].contains(trimmedTeacher.lowercased()) {
                copy.classes[index].teacher = ""
            }
            if ["room", "room #"].contains(trimmedRoom.lowercased()) {
                copy.classes[index].room = ""
            }
        }

        return copy
    }
}
