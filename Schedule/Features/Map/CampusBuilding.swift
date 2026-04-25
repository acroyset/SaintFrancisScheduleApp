//
//  CampusBuilding.swift
//  Schedule
//

import Foundation

struct CampusBuilding: Identifiable, Equatable {
    let id: String
    let title: String
    let normalizedX: Double
    let normalizedY: Double
}

struct CampusClassLocation: Identifiable, Equatable {
    let id: String
    let periodLabel: String
    let className: String
    let room: String
    let building: CampusBuilding
}

enum CampusMapData {
    static let innovationCenter = CampusBuilding(
        id: "innovationCenter",
        title: "Edgars Innovation Center 1100's 1200's",
        normalizedX: 0.26,
        normalizedY: 0.09
    )

    static let cafeteria = CampusBuilding(
        id: "cafeteria",
        title: "Cafeteria",
        normalizedX: 0.13,
        normalizedY: 0.22
    )

    static let sobratoCommons = CampusBuilding(
        id: "sobratoCommons",
        title: "Sobrato Commons 200's",
        normalizedX: 0.31,
        normalizedY: 0.38
    )

    static let theater = CampusBuilding(
        id: "theater",
        title: "Theater",
        normalizedX: 0.46,
        normalizedY: 0.08
    )

    static let alumniGym = CampusBuilding(
        id: "alumniGym",
        title: "Alumni Gym",
        normalizedX: 0.47,
        normalizedY: 0.22
    )

    static let burnsGym = CampusBuilding(
        id: "burnsGym",
        title: "Burns Gym",
        normalizedX: 0.46,
        normalizedY: 0.34
    )

    static let aquaticCenter = CampusBuilding(
        id: "aquaticCenter",
        title: "Aquatic Center",
        normalizedX: 0.63,
        normalizedY: 0.18
    )

    static let fourHundreds = CampusBuilding(
        id: "fourHundreds",
        title: "400's",
        normalizedX: 0.43,
        normalizedY: 0.46
    )

    static let fiveHundreds = CampusBuilding(
        id: "fiveHundreds",
        title: "500's",
        normalizedX: 0.43,
        normalizedY: 0.57
    )

    static let sixHundreds = CampusBuilding(
        id: "sixHundreds",
        title: "600's",
        normalizedX: 0.33,
        normalizedY: 0.64
    )

    static let andreHouse = CampusBuilding(
        id: "andreHouse",
        title: "Andre House",
        normalizedX: 0.35,
        normalizedY: 0.50
    )

    static let allBuildings: [CampusBuilding] = [
        innovationCenter,
        cafeteria,
        sobratoCommons,
        theater,
        alumniGym,
        burnsGym,
        aquaticCenter,
        fourHundreds,
        fiveHundreds,
        sixHundreds,
        andreHouse
    ]

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
        let normalized = room
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "room", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

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

        guard let roomNumber = Int(normalized.filter(\.isNumber)) else {
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
