//
//  ClassItem.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation

struct ClassItem: Equatable, Codable {
    var name: String
    var teacher: String
    var room: String
    
    static func == (a: ClassItem, b: ClassItem) -> Bool {
        return (a.name == b.name && a.room == b.room && a.teacher == b.teacher)
    }
}
