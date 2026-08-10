//
//  ClassItem.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation

struct ClassItem: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var teacher: String
    var room: String
    private(set) var needsIDMigration: Bool

    init(
        id: UUID = UUID(),
        name: String,
        teacher: String,
        room: String,
        needsIDMigration: Bool = false
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.room = room
        self.needsIDMigration = needsIDMigration
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case teacher
        case room
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id)
        id = decodedID ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        teacher = try container.decode(String.self, forKey: .teacher)
        room = try container.decode(String.self, forKey: .room)
        needsIDMigration = decodedID == nil
    }

    static func == (lhs: ClassItem, rhs: ClassItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.teacher == rhs.teacher &&
            lhs.room == rhs.room
    }
}
