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
    var isSecondLunch: Bool = false  // NEW: Track lunch preference
}
