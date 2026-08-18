//
//  SpecialSchedule.swift
//  Schedule
//

import Foundation

/// Parses the same `$class - start - end` format used by Days.txt.
/// The code is supplied by the Google Sheet's "Special Day Code" column.
struct SpecialSchedule {
    let day: Day

    init?(code: String) {
        let normalizedCode = code
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")

        var name = "Special"
        var names: [String] = []
        var startTimes: [Time] = []
        var endTimes: [Time] = []

        for rawLine in normalizedCode.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.caseInsensitiveCompare("$end") != .orderedSame else {
                continue
            }

            let parts = line.split(
                separator: "-",
                maxSplits: 2,
                omittingEmptySubsequences: false
            ).map { String($0).trimmingCharacters(in: .whitespaces) }

            if parts.count == 3,
               !parts[0].isEmpty,
               let start = Self.parseTime(parts[1]),
               let end = Self.parseTime(parts[2]),
               start < end {
                names.append(parts[0])
                startTimes.append(start)
                endTimes.append(end)
            } else if names.isEmpty, !line.hasPrefix("$") {
                name = line
            } else {
                return nil
            }
        }

        guard !names.isEmpty else { return nil }
        day = Day(name: name, names: names, startTimes: startTimes, endTimes: endTimes)
    }

    private static func parseTime(_ value: String) -> Time? {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count),
              let hour = Int(components[0]),
              (1...23).contains(hour) else {
            return nil
        }

        let minute = components.count > 1 ? Int(components[1]) : 0
        let second = components.count > 2 ? Int(components[2]) : 0
        guard let minute, let second,
              (0...59).contains(minute),
              (0...59).contains(second) else {
            return nil
        }

        return Time(value)
    }
}
