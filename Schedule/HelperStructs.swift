//
//  Structs.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//
import SwiftUI

struct ScheduleData {
    var classes: [ClassItem]
    var days: [Day]
    var isSecondLunch: Bool = false  // NEW: Track lunch preference
}

struct ClassItem: Equatable {
    var name: String
    var teacher: String
    var room: String
    
    static func == (a: ClassItem, b: ClassItem) -> Bool {
        return (a.name == b.name && a.room == b.room && a.teacher == b.teacher)
    }
}

struct Day {
    var name = ""
    var names: [String] = []
    var startTimes: [Time] = []
    var endTimes: [Time] = []
    var note = ""
}

enum Window: Int {
    case Home = 0
    case News = 1
    case Clubs = 2
    case ClassEditor = 3
    case Settings = 4
    case Profile = 5
}

enum TutorialState: Int {
    case Hidden = 0
    case Intro = 1
    case DateNavigator = 2
    case News = 3
    case ClassEditor = 4
    case Settings = 5
    case Profile = 6
    case Outro = 7
}

extension Color {
    func highContrastTextColor() -> Color {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        // luminance calculation (WCAG)
        let luminance = 0.299*r + 0.587*g + 0.114*b
        return luminance > 0.5 ?
        Color(hue: 0, saturation: 0, brightness: 0.4) :
        Color(hue: 0,saturation: 0,brightness: 0.6)
    }
}
