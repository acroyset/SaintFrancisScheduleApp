//
//  NewsSource.swift
//  Schedule
//

import Foundation

enum NewsSource: String, CaseIterable, Identifiable {
    case dailyAnnouncements
    case lancerLive
    case athletics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyAnnouncements:
            return "Daily Announcements"
        case .lancerLive:
            return "Lancer Live"
        case .athletics:
            return "Athletics"
        }
    }
}
