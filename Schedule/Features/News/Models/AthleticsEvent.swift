//
//  AthleticsEvent.swift
//  Schedule
//

import Foundation

struct AthleticsSchedule {
    let upcoming: [AthleticsEvent]
    let recent: [AthleticsEvent]
}

struct AthleticsEvent: Identifiable, Equatable {
    let id: Int
    let date: Date?
    let dateText: String
    let time: String
    let sportTitle: String
    let opponentTitle: String
    let location: String
    let locationIndicator: String
    let resultStatus: String?
    let teamScore: String?
    let opponentScore: String?
    let scheduleURL: URL?
    let isTBD: Bool

    var matchupText: String {
        let prefix: String
        switch locationIndicator {
        case "A":
            prefix = "at"
        case "H":
            prefix = "vs"
        default:
            prefix = "vs"
        }

        return "\(prefix) \(opponentTitle)"
    }

    var timeText: String {
        if isTBD {
            return "TBD"
        }

        return time.isEmpty ? "All day" : time
    }

    var resultText: String? {
        guard let resultStatus else { return nil }

        let label: String
        switch resultStatus {
        case "W":
            label = "Win"
        case "L":
            label = "Loss"
        case "T":
            label = "Tie"
        case "P":
            return "Postponed"
        case "C":
            return "Cancelled"
        default:
            label = resultStatus
        }

        guard let teamScore, let opponentScore else {
            return label
        }

        return "\(label), \(teamScore)-\(opponentScore)"
    }
}
