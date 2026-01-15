//
//  CSVParser.swift
//  Schedule
//
//  Created by Andreas Royset on 1/14/26.
//

import Foundation

struct CSVParser {
    /// Properly parse CSV with support for quoted fields containing commas
    static func parseScheduleCSV(_ csvString: String) -> [String: [String]]? {
        var result: [String: [String]] = [:]
        let lines = csvString.components(separatedBy: .newlines)
        
        guard lines.count > 1 else {
            print("❌ CSV: Empty or invalid CSV data")
            return nil
        }
        
        // Skip header row
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let columns = parseCSVLine(trimmed)
            guard columns.count >= 3 else {
                print("⚠️ CSV: Skipping malformed line: \(trimmed)")
                continue
            }
            
            let date = columns[0].trimmingCharacters(in: .whitespaces)
            let dayType = columns[1].trimmingCharacters(in: .whitespaces)
            let note = columns[2].trimmingCharacters(in: .whitespaces)
            
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
            
            result[date] = [dayType, note]
        }
        
        guard !result.isEmpty else {
            print("❌ CSV: No valid schedule entries parsed")
            return nil
        }
        
        return result
    }
    
    /// Parse a single CSV line, properly handling quoted fields
    private static func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let char = line[i]
            
            if char == "\"" {
                let nextIndex = line.index(after: i)
                // Check for escaped quote ("")
                if nextIndex < line.endIndex && line[nextIndex] == "\"" {
                    currentField.append("\"")
                    i = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if char == "," && !isInsideQuotes {
                columns.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
            
            i = line.index(after: i)
        }
        
        // Add the last field
        columns.append(currentField)
        
        return columns
    }
    
    /// Validate date is in MM-dd-yy format
    private static func isValidDateFormat(_ dateString: String) -> Bool {
        let pattern = "^\\d{1,2}-\\d{2}-\\d{2}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(dateString.startIndex..<dateString.endIndex, in: dateString)
        return regex.firstMatch(in: dateString, range: range) != nil
    }
}
