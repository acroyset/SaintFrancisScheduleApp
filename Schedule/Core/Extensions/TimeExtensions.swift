//
//  TimeExtensions.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

extension Time {
    func toDate() -> Date {
        var components = DateComponents()
        components.hour = self.h
        components.minute = self.m
        components.second = self.s
        return Calendar.current.date(from: components) ?? Date()
    }
    
    static func fromDate(_ date: Date) -> Time {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Time(
            h: comps.hour ?? 0,
            m: comps.minute ?? 0,
            s: comps.second ?? 0
        )
    }
}
