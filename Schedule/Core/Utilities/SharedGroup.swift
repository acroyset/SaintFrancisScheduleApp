//
//  SharedGroup.swift
//  Schedule
//
//  Created by Andreas Royset on 9/4/25.
//

import Foundation

enum SharedGroup {
    static let id  = "group.Xcode.ScheduleApp"
    static let key = "ScheduleLines"            
    static var defaults: UserDefaults { UserDefaults(suiteName: id)! }
}
