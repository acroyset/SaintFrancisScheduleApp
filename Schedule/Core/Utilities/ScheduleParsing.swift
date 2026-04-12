//
//  ScheduleParsing.swift
//  Schedule
//

import Foundation

enum ScheduleParsing {
    static func parseClass(_ line: String) -> ClassItem {
        let parts = line.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 4 { return ClassItem(name: parts[3], teacher: parts[1], room: parts[2]) }
        if parts.count == 3 { return ClassItem(name: parts[0], teacher: parts[1], room: parts[2]) }
        return ClassItem(name: "None", teacher: "None", room: "None")
    }

    static func parseDays(_ contents: String) -> [Day] {
        var days: [Day] = []
        var currentDay = Day()

        for raw in contents.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "$end" {
                days.append(currentDay)
                currentDay = Day()
                continue
            }

            let parts = line.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 3 {
                currentDay.names.append(parts[0])
                currentDay.startTimes.append(Time(parts[1]))
                currentDay.endTimes.append(Time(parts[2]))
            } else if let first = parts.first {
                currentDay.name = first
            }
        }

        return days
    }
}
