//
//  Time.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//
import Foundation

struct Time: Comparable, Equatable, Codable {
    var h: Int, m: Int, s: Int

    static func now() -> Time {
        let c = Calendar.current.dateComponents([.hour,.minute,.second], from: Date())
        return Time(h: c.hour ?? 0, m: c.minute ?? 0, s: c.second ?? 0)
    }

    init(h: Int, m: Int, s: Int) { self.h = h; self.m = m; self.s = s }

    init(_ str: String) {
        let p = str.split(separator: ":").compactMap { Int($0) }
        switch p.count {
        case 1: self.init(h: p[0], m: 0, s: 0)
        case 2: self.init(h: p[0], m: p[1], s: 0)
        default: self.init(h: p[0], m: p[1], s: p.count > 2 ? p[2] : 0)
        }
        if h < 7 { h += 12 }
    }

    func string(showSeconds: Bool = false) -> String {
        var hr = h; if hr > 12 { hr -= 12 }
        let mm = String(format: "%02d", m)
        let ss = String(format: "%02d", s)
        return showSeconds ? "\(hr):\(mm):\(ss)" : (ss == "00" ? "\(hr):\(mm)" : "\(hr):\(mm):\(ss)")
    }

    static func < (a: Time, b: Time) -> Bool { (a.h,a.m,a.s) < (b.h,b.m,b.s) }
        
    init(seconds: Int) {
        h = seconds / 3600
        m = (seconds % 3600) / 60
        s = seconds % 60
    }
}

extension Time {
    var seconds: Int { h * 3600 + m * 60 + s }
}

extension Time {
    // Convert this Time to a Date on "today" (date portion is irrelevant for .hourAndMinute DatePickers)
    func toDate(on date: Date = Date()) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = h
        comps.minute = m
        comps.second = s
        return Calendar.current.date(from: comps) ?? date
    }
    
    // Build a Time from a Date’s hour/minute/second
    static func fromDate(_ date: Date) -> Time {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Time(h: comps.hour ?? 0, m: comps.minute ?? 0, s: comps.second ?? 0)
    }
}
