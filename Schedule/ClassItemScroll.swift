//
//  ClassItemScroll.swift
//  Schedule
//
//  Created by Andreas Royset on 9/5/25.
//

import Foundation
import SwiftUI

struct ClassItemScroll: View {
    var scheduleLines: [ScheduleLine]
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var note: String
    var dayCode: String
    var output: String
    var isToday: Bool
    var iPad: Bool
    @Binding var scrollTarget: Int?
    @Binding var addEvent: Bool
    
    // Configuration for proportional sizing
    var body: some View {
            let now = Time.now()
            let nowSec = now.seconds

            let linesToShow = makeDisplayLines(from: scheduleLines, nowSec: nowSec, isToday: isToday)

            ScrollView {
            VStack(spacing: 8) {
                if !output.isEmpty && scheduleLines.isEmpty {
                    Text(output)
                        .font(.system(
                            size: iPad ? 35 : 17,
                            design: .monospaced
                        ))
                        .foregroundColor(PrimaryColor)
                }
                
                ForEach(Array(linesToShow.enumerated()), id: \.0) { i, line in
                    rowView(
                        line,
                        note : note,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .id(i)
                }
                
                Button {
                    addEvent = true
                } label: {
                    VStack{
                        Text("+")
                            .font(.system(
                                size: iPad ? 48 : 36,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .foregroundStyle(PrimaryColor)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(12)
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal)
        }
        .id(dayCode)
        .scrollPosition(id: $scrollTarget, anchor: .center)
    }
    
    private func makeDisplayLines(from src: [ScheduleLine], nowSec: Int, isToday: Bool) -> [ScheduleLine] {
            guard !src.isEmpty else { return [] }

            var out: [ScheduleLine] = []
            for i in src.indices {
                let line = src[i]
                out.append(augmented(line: line, nowSec: nowSec, isToday: isToday))

                // insert a "Free Time" row between items if there’s a gap > 10 min
                if i > 0 {
                    if line.content != "" { continue }
                    let prevEnd = Time(seconds: src[i-1].endSec ?? 0)
                    let start   = Time(seconds: line.startSec ?? 0)
                    if start.seconds - prevEnd.seconds > 600 {
                        let isCurrent = (prevEnd.seconds <= nowSec && nowSec < start.seconds) && isToday
                        let p = progressValue(start: prevEnd.seconds, end: start.seconds, now: nowSec)

                        out.insert(ScheduleLine(
                            content: "",
                            isCurrentClass: isCurrent,
                            timeRange: "\(prevEnd.string()) to \(start.string())",
                            className: "\((start.seconds-prevEnd.seconds)/60) min",
                            teacher: "",
                            room: "",
                            startSec: prevEnd.seconds,
                            endSec: start.seconds,
                            progress: p),
                            at: i+1
                        )
                    }
                }
            }
            return out
        }

        private func augmented(line: ScheduleLine, nowSec: Int, isToday: Bool) -> ScheduleLine {
            var l = line
            let isCurrent = (l.startSec ?? 0) <= nowSec && nowSec < (l.endSec ?? 0) && isToday
            l.isCurrentClass = isCurrent
            l.progress = progressValue(start: l.startSec ?? 0, end: l.endSec ?? 0, now: nowSec)
            return l
        }
}
