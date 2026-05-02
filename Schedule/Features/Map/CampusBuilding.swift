//
//  CampusBuilding.swift
//  Schedule
//

import CoreGraphics
import Foundation

struct CampusBuilding: Identifiable, Equatable {
    let id: String
    let title: String
    let normalizedX: Double
    let normalizedY: Double
    let floorCount: Int
}

struct CampusClassLocation: Identifiable, Equatable {
    let id: String
    let periodLabel: String
    let className: String
    let room: String
    let building: CampusBuilding
}

struct CampusRoomMarker: Identifiable, Equatable {
    let room: String
    let building: CampusBuilding
    let normalizedX: Double
    let normalizedY: Double
    let layer: CampusMapLayer

    var id: String { room }
}

enum CampusMapLayer: Int, CaseIterable, Identifiable {
    case first = 1
    case second = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .first:
            return "1st Floor"
        case .second:
            return "2nd Floor"
        }
    }

    var shortTitle: String {
        switch self {
        case .first:
            return "1"
        case .second:
            return "2"
        }
    }
}

enum CampusMapData {
    static let innovationCenter = CampusBuilding(
        id: "innovationCenter",
        title: "Edgars Innovation Center 1100's 1200's",
        normalizedX: 0.26,
        normalizedY: 0.09,
        floorCount: 2
    )

    static let cafeteria = CampusBuilding(
        id: "cafeteria",
        title: "Cafeteria",
        normalizedX: 0.13,
        normalizedY: 0.22,
        floorCount: 1
    )

    static let sobratoCommons = CampusBuilding(
        id: "sobratoCommons",
        title: "Sobrato Commons 200's",
        normalizedX: 0.31,
        normalizedY: 0.38,
        floorCount: 1
    )

    static let library = CampusBuilding(
        id: "library",
        title: "Library",
        normalizedX: 0.21,
        normalizedY: 0.36,
        floorCount: 1
    )

    static let theater = CampusBuilding(
        id: "theater",
        title: "Theater",
        normalizedX: 0.46,
        normalizedY: 0.08,
        floorCount: 1
    )

    static let alumniGym = CampusBuilding(
        id: "alumniGym",
        title: "Alumni Gym",
        normalizedX: 0.47,
        normalizedY: 0.22,
        floorCount: 1
    )

    static let burnsGym = CampusBuilding(
        id: "burnsGym",
        title: "Burns Gym",
        normalizedX: 0.46,
        normalizedY: 0.34,
        floorCount: 1
    )

    static let aquaticCenter = CampusBuilding(
        id: "aquaticCenter",
        title: "Aquatic Center",
        normalizedX: 0.63,
        normalizedY: 0.18,
        floorCount: 1
    )

    static let fourHundreds = CampusBuilding(
        id: "fourHundreds",
        title: "400's",
        normalizedX: 0.43,
        normalizedY: 0.46,
        floorCount: 2
    )

    static let fiveHundreds = CampusBuilding(
        id: "fiveHundreds",
        title: "500's",
        normalizedX: 0.43,
        normalizedY: 0.57,
        floorCount: 2
    )

    static let sixHundreds = CampusBuilding(
        id: "sixHundreds",
        title: "600's",
        normalizedX: 0.33,
        normalizedY: 0.64,
        floorCount: 2
    )

    static let andreHouse = CampusBuilding(
        id: "andreHouse",
        title: "Andre House",
        normalizedX: 0.35,
        normalizedY: 0.50,
        floorCount: 1
    )

    static let allBuildings: [CampusBuilding] = [
        innovationCenter,
        cafeteria,
        sobratoCommons,
        library,
        theater,
        alumniGym,
        burnsGym,
        aquaticCenter,
        fourHundreds,
        fiveHundreds,
        sixHundreds,
        andreHouse
    ]

    static let roomMarkers: [CampusRoomMarker] = [
        roomRow(
            building: innovationCenter,
            prefix: 1100,
            numbers: Array(1...8),
            from: CGPoint(x: 0.185, y: 0.055),
            to: CGPoint(x: 0.315, y: 0.055),
            layer: .first
        ),
        roomRow(
            building: innovationCenter,
            prefix: 1100,
            numbers: [14, 13, 12, 11],
            from: CGPoint(x: 0.315, y: 0.132),
            to: CGPoint(x: 0.225, y: 0.132),
            layer: .first
        ),
        roomRow(
            building: innovationCenter,
            prefix: 1200,
            numbers: Array(1...8),
            from: CGPoint(x: 0.185, y: 0.055),
            to: CGPoint(x: 0.315, y: 0.055),
            layer: .second
        ),
        roomRow(
            building: innovationCenter,
            prefix: 1200,
            numbers: [14, 13, 12, 11, 10],
            from: CGPoint(x: 0.315, y: 0.132),
            to: CGPoint(x: 0.205, y: 0.132),
            layer: .second
        ),
        roomRow(
            building: sobratoCommons,
            prefix: 200,
            numbers: [0, 2, 4, 6],
            from: CGPoint(x: 0.265, y: 0.405),
            to: CGPoint(x: 0.355, y: 0.405),
            layer: .first
        ),
        roomRow(
            building: sobratoCommons,
            prefix: 200,
            numbers: [1, 3, 5, 7],
            from: CGPoint(x: 0.265, y: 0.355),
            to: CGPoint(x: 0.355, y: 0.355),
            layer: .first
        ),
        roomRow(
            building: fourHundreds,
            prefix: 400,
            numbers: [1, 2, 3],
            from: CGPoint(x: 0.405, y: 0.438),
            to: CGPoint(x: 0.455, y: 0.438),
            layer: .first
        ),
        roomRow(
            building: fourHundreds,
            prefix: 400,
            numbers: [21, 22, 23],
            from: CGPoint(x: 0.405, y: 0.438),
            to: CGPoint(x: 0.455, y: 0.438),
            layer: .second
        ),
        [
            roomMarker(building: fiveHundreds, room: 501, x: 0.405, y: 0.462, layer: .first),
            roomMarker(building: fiveHundreds, room: 502, x: 0.405, y: 0.486, layer: .first),
            roomMarker(building: fiveHundreds, room: 503, x: 0.405, y: 0.510, layer: .first),
            roomMarker(building: fiveHundreds, room: 504, x: 0.405, y: 0.534, layer: .first),
            roomMarker(building: fiveHundreds, room: 505, x: 0.455, y: 0.534, layer: .first),
            roomMarker(building: fiveHundreds, room: 506, x: 0.405, y: 0.558, layer: .first),
            roomMarker(building: fiveHundreds, room: 507, x: 0.455, y: 0.558, layer: .first),
            roomMarker(building: fiveHundreds, room: 521, x: 0.405, y: 0.462, layer: .second),
            roomMarker(building: fiveHundreds, room: 522, x: 0.405, y: 0.486, layer: .second),
            roomMarker(building: fiveHundreds, room: 523, x: 0.405, y: 0.510, layer: .second),
            roomMarker(building: fiveHundreds, room: 524, x: 0.405, y: 0.534, layer: .second),
            roomMarker(building: fiveHundreds, room: 525, x: 0.455, y: 0.534, layer: .second),
            roomMarker(building: fiveHundreds, room: 526, x: 0.405, y: 0.558, layer: .second),
            roomMarker(building: fiveHundreds, room: 527, x: 0.455, y: 0.558, layer: .second),
            roomMarker(building: sixHundreds, room: 601, x: 0.285, y: 0.615, layer: .first),
            roomMarker(building: sixHundreds, room: 602, x: 0.315, y: 0.615, layer: .first),
            roomMarker(building: sixHundreds, room: 603, x: 0.345, y: 0.615, layer: .first),
            roomMarker(building: sixHundreds, room: 604, x: 0.375, y: 0.615, layer: .first),
            roomMarker(building: sixHundreds, room: 600, x: 0.285, y: 0.645, layer: .first),
            roomMarker(building: sixHundreds, room: 620, x: 0.255, y: 0.615, layer: .second),
            roomMarker(building: sixHundreds, room: 622, x: 0.285, y: 0.615, layer: .second),
            roomMarker(building: sixHundreds, room: 623, x: 0.315, y: 0.615, layer: .second),
            roomMarker(building: sixHundreds, room: 624, x: 0.345, y: 0.615, layer: .second),
            roomMarker(building: sixHundreds, room: 625, x: 0.375, y: 0.615, layer: .second),
            roomMarker(building: sixHundreds, room: 626, x: 0.405, y: 0.615, layer: .second),
            roomMarker(building: sixHundreds, room: 621, x: 0.285, y: 0.645, layer: .second),
            roomMarker(building: sixHundreds, room: 619, x: 0.315, y: 0.645, layer: .second)
        ]
    ].flatMap { $0 }

    private static func roomMarker(
        building: CampusBuilding,
        room: Int,
        x: Double,
        y: Double,
        layer: CampusMapLayer
    ) -> CampusRoomMarker {
        CampusRoomMarker(
            room: "\(room)",
            building: building,
            normalizedX: x,
            normalizedY: y,
            layer: layer
        )
    }

    static func locations(for classes: [ClassItem]) -> [CampusClassLocation] {
        classes.enumerated().compactMap { index, classItem in
            let trimmedRoom = classItem.room.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = classItem.name.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedRoom.isEmpty,
                  !trimmedName.isEmpty,
                  trimmedRoom.lowercased() != "n",
                  trimmedRoom.lowercased() != "room",
                  let building = building(forRoom: trimmedRoom) else {
                return nil
            }

            return CampusClassLocation(
                id: "\(index)-\(trimmedName)-\(trimmedRoom)",
                periodLabel: periodLabel(for: index, fallback: trimmedName),
                className: trimmedName,
                room: trimmedRoom,
                building: building
            )
        }
    }

    static func building(forRoom room: String) -> CampusBuilding? {
        let normalized = normalizedRoomText(room)

        if normalized.contains("burns") {
            return burnsGym
        }
        if normalized.contains("alumni") {
            return alumniGym
        }
        if normalized.contains("gym") || normalized.contains("liturgy") {
            return burnsGym
        }
        if normalized.contains("pool") || normalized.contains("aquatic") {
            return aquaticCenter
        }
        if normalized.contains("theater") || normalized.contains("theatre") || normalized.contains("graham") {
            return theater
        }
        if normalized.contains("andre") {
            return andreHouse
        }
        if normalized.contains("caf") || normalized.contains("lunch") {
            return cafeteria
        }

        guard let roomNumber = roomNumber(from: normalized) else {
            return nil
        }

        switch roomNumber {
        case 1100...1299:
            return innovationCenter
        case 200...299:
            return sobratoCommons
        case 400...499:
            return fourHundreds
        case 500...599:
            return fiveHundreds
        case 600...699:
            return sixHundreds
        default:
            return nil
        }
    }

    static func roomKey(for room: String) -> String {
        let normalized = normalizedRoomText(room)
        if let roomNumber = roomNumber(from: normalized) {
            return "\(roomNumber)"
        }

        return normalized
    }

    private static func roomNumber(from room: String) -> Int? {
        Int(room.filter(\.isNumber))
    }

    private static func normalizedRoomText(_ room: String) -> String {
        room
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "room", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func roomRow(
        building: CampusBuilding,
        prefix: Int,
        numbers: [Int],
        from start: CGPoint,
        to end: CGPoint,
        layer: CampusMapLayer
    ) -> [CampusRoomMarker] {
        guard !numbers.isEmpty else { return [] }

        return numbers.enumerated().map { index, number in
            let progress = numbers.count == 1 ? 0 : Double(index) / Double(numbers.count - 1)
            let x = start.x + ((end.x - start.x) * progress)
            let y = start.y + ((end.y - start.y) * progress)

            return CampusRoomMarker(
                room: "\(prefix + number)",
                building: building,
                normalizedX: x,
                normalizedY: y,
                layer: layer
            )
        }
    }

    private static func periodLabel(for index: Int, fallback: String) -> String {
        switch index {
        case 0:
            return "1st"
        case 1:
            return "2nd"
        case 2:
            return "3rd"
        case 3...6:
            return "\(index + 1)th"
        case 9:
            return "Advisory"
        case 12:
            return "Homeroom"
        default:
            return fallback
        }
    }
}
