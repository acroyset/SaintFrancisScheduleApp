//
//  SimpleEntry.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import WidgetKit
import SwiftUI

struct SimpleEntry: TimelineEntry, Hashable {
    let date: Date
    let lines: [ScheduleLine]
    let dayCode: String
    
    var isDataStale: Bool {
        let lastAppUpdate = SharedGroup.defaults.object(forKey: "LastAppDataUpdate") as? Date ?? Date.distantPast
        return Date().timeIntervalSince(lastAppUpdate) > 1800 // 30 minutes
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(dayCode)
    }
    
    static func == (lhs: SimpleEntry, rhs: SimpleEntry) -> Bool {
        return lhs.date == rhs.date && lhs.dayCode == rhs.dayCode
    }
}
