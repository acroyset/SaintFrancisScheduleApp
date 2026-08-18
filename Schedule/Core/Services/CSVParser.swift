//
//  CSVParser.swift
//  Schedule
//
//  Created by Andreas Royset on 1/14/26.
//

import Foundation

struct CSVParser {
    /// Parses the schedule export, including multiline special-day code cells.
    static func parseScheduleCSV(_ csvString: String) -> [String: [String]]? {
        var result: [String: [String]] = [:]
        let rows = parseCSVRows(csvString)

        guard let header = rows.first, rows.count > 1 else {
            print("❌ CSV: Empty or invalid CSV data")
            return nil
        }

        let normalizedHeader = header.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let dayIndex = normalizedHeader.firstIndex(of: "day") ?? 1
        let noteIndex = normalizedHeader.firstIndex(of: "note") ?? 2

        for columns in rows.dropFirst() {
            guard !columns.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            guard columns.indices.contains(0),
                  columns.indices.contains(dayIndex) else {
                print("⚠️ CSV: Skipping malformed row")
                continue
            }

            let date = columns[0].trimmingCharacters(in: .whitespaces)
            let dayType = columns[dayIndex].trimmingCharacters(in: .whitespaces)
            let note = columns.indices.contains(noteIndex)
                ? columns[noteIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            // Column E (the fifth CSV column) contains the optional Days.txt-style
            // override. It only applies to S1; a blank cell keeps the normal
            // Activity schedule from Days.txt.
            let specialCode = dayType.caseInsensitiveCompare("s1") == .orderedSame
                && columns.indices.contains(4)
                ? columns[4].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            // Validate date format (MM-dd-yy)
            guard isValidDateFormat(date) else {
                print("⚠️ CSV: Invalid date format: \(date)")
                continue
            }
            
            // Validate day type is not empty
            guard !dayType.isEmpty else {
                print("⚠️ CSV: Empty day type for date: \(date)")
                continue
            }
            
            result[date] = [dayType, note, specialCode]
        }
        
        guard !result.isEmpty else {
            print("❌ CSV: No valid schedule entries parsed")
            return nil
        }
        
        return result
    }

    /// Parses the lightweight Google Visualization response used to repair a
    /// legacy two-column S1 cache. That response contains only columns A and E.
    static func parseSpecialCodeCSV(_ csvString: String, dateKey: String) -> String? {
        let rows = parseCSVRows(csvString)

        for columns in rows.dropFirst() where columns.indices.contains(1) {
            let date = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard date == dateKey else { continue }
            return columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
    
    /// Parses full CSV records so quoted Google Sheets cells may contain newlines.
    private static func parseCSVRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let char = csv[index]

            if char == "\"" {
                let nextIndex = csv.index(after: index)
                if isInsideQuotes, nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if char == "," && !isInsideQuotes {
                row.append(field)
                field = ""
            } else if (char == "\n" || char == "\r") && !isInsideQuotes {
                if char == "\r" {
                    let nextIndex = csv.index(after: index)
                    if nextIndex < csv.endIndex, csv[nextIndex] == "\n" {
                        index = nextIndex
                    }
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }

            index = csv.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
    
    /// Validate date is in MM-dd-yy format
    private static func isValidDateFormat(_ dateString: String) -> Bool {
        let pattern = "^\\d{1,2}-\\d{2}-\\d{2}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(dateString.startIndex..<dateString.endIndex, in: dateString)
        return regex.firstMatch(in: dateString, range: range) != nil
    }
}
