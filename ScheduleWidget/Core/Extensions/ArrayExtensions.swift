//
//  ArrayExtensions.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

extension Array where Element == ScheduleLine {
    func currentAndNextOrPrev(nowSec: Int) -> [ScheduleLine] {
        // Update progress values in real-time for current classes
        var updatedLines = self.map { line -> ScheduleLine in
            var updatedLine = line
            if let start = line.startSec, let end = line.endSec {
                let progress = progressValue(start: start, end: end, now: nowSec)
                updatedLine.progress = progress
                updatedLine.isCurrentClass = nowSec >= start && nowSec < end
            }
            return updatedLine
        }
        
        // 1. Try to find current class based on time
        if let currentIdx = updatedLines.firstIndex(where: { $0.isCurrentClass }) {
            if currentIdx == endIndex - 1 {
                if indices.contains(currentIdx - 1) {
                    return [updatedLines[currentIdx - 1], updatedLines[currentIdx]]
                } else {
                    return [updatedLines[currentIdx]]
                }
            }
            var out = [updatedLines[currentIdx]]
            if indices.contains(currentIdx + 1) { out.append(updatedLines[currentIdx + 1]) }
            return out
        }

        // 2. No current class — find the first upcoming
        if let upcomingIdx = updatedLines.firstIndex(where: { ($0.startSec ?? .max) > nowSec }) {
            var out = [updatedLines[upcomingIdx]]
            if indices.contains(upcomingIdx + 1) { out.append(updatedLines[upcomingIdx + 1]) }
            return out
        }

        // 3. Fallback — return last two or less
        return Array(updatedLines.suffix(2))
    }
}
