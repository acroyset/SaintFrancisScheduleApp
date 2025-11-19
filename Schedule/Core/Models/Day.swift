//
//  Day.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation

struct Day: Codable {
    var name = ""
    var names: [String] = []
    var startTimes: [Time] = []
    var endTimes: [Time] = []
    var note = ""
}
