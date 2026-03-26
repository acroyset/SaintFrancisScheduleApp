//
//  NowNextCard.swift
//  Schedule
//
//  Created by Andreas Royset on 3/25/26.
//
//
//  Prominent always-visible card showing current class, time remaining,
//  and next class. Replaces the cognitive work of scanning the list.
//

import SwiftUI

struct NowNextCard: View {
    let scheduleLines: [ScheduleLine]
    let dayCode:       String
    let note:          String
    let isToday:       Bool
    let PrimaryColor:  Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    // MARK: - Derived state (recomputed on every render; parent ticks every 1s)

    private var nowSec: Int { Time.now().seconds }

    private var realClasses: [ScheduleLine] {
        scheduleLines.filter { $0.startSec != nil && $0.endSec != nil && $0.className != "Passing Period" }
    }

    private var currentClass: ScheduleLine? {
        guard isToday else { return nil }
        let n = nowSec
        return realClasses.first { ($0.startSec ?? Int.max) <= n && n < ($0.endSec ?? 0) }
    }

    private var nextClass: ScheduleLine? {
        let n = nowSec
        return realClasses.first { ($0.startSec ?? Int.max) > n }
    }

    private var isDoneForDay: Bool {
        guard isToday, !realClasses.isEmpty else { return false }
        return !realClasses.contains { ($0.endSec ?? 0) > nowSec }
    }

    private func displayName(_ line: ScheduleLine) -> String {
        line.className == "Activity" ? (note.isEmpty ? "Activity" : note) : line.className
    }

    // MARK: - Body

    var body: some View {
        Group {
            if !isToday {
                // Browsing another day — no card needed
                EmptyView()
            } else if isDoneForDay {
                doneCard
            } else if let cur = currentClass {
                inClassCard(cur)
            } else if let nxt = nextClass {
                upNextCard(nxt)
            }
        }
    }

    // MARK: - In Class card

    private func inClassCard(_ line: ScheduleLine) -> some View {
        let secsLeft   = max(0, (line.endSec ?? nowSec) - nowSec)
        let minsLeft   = secsLeft / 60
        let isUrgent   = secsLeft < 300          // < 5 min
        let progress   = line.progress ?? 0

        return VStack(spacing: 0) {
            // ── Main row ──────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {

                // Left: status + name + meta
                VStack(alignment: .leading, spacing: 5) {
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(TertiaryColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: (TertiaryColor).opacity(0.6),
                                    radius: isUrgent ? 4 : 0)
                        Text("IN CLASS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor.opacity(0.8))
                            .tracking(1.2)
                    }

                    // Class name — dominant
                    Text(displayName(line))
                        .font(.system(size: iPad ? 26 : 20, weight: .black, design: .rounded))
                        .foregroundColor(TertiaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    // Room + time range
                    HStack(spacing: 10) {
                        if !line.room.isEmpty {
                            Label(line.room, systemImage: "mappin.circle.fill")
                                .font(.system(size: iPad ? 13 : 11, weight: .semibold))
                                .foregroundColor(TertiaryColor.opacity(0.85))
                        }
                        if !line.teacher.isEmpty {
                            Text(line.teacher)
                                .font(.system(size: iPad ? 12 : 10, weight: .medium))
                                .foregroundColor(TertiaryColor.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Right: big countdown
                VStack(alignment: .trailing, spacing: 1) {
                    if secsLeft < 60 {
                        Text("\(secsLeft)")
                            .font(.system(size: iPad ? 48 : 38, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("SEC LEFT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor.opacity(0.85))
                            .tracking(0.8)
                    } else {
                        Text("\(minsLeft)")
                            .font(.system(size: iPad ? 48 : 38, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("MIN LEFT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor.opacity(0.75))
                            .tracking(0.8)
                    }
                }
            }
            .padding(.horizontal, iPad ? 18 : 14)
            .padding(.top, iPad ? 14 : 12)
            .padding(.bottom, 10)

            // ── Progress bar ──────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TertiaryColor.opacity(0.15))
                    Rectangle()
                        .fill(LinearGradient(colors: [TertiaryColor.opacity(0.9), TertiaryColor.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress))
                        .animation(.linear(duration: 0.5), value: progress)
                }
            }
            .frame(height: 3)

            // ── Next class footer ─────────────────────────────────────
            if let nxt = nextClass {
                HStack(spacing: 0) {
                    Text("NEXT ")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(TertiaryColor.opacity(0.5))
                        .tracking(0.5)
                    Text(displayName(nxt))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(TertiaryColor.opacity(0.75))
                        .lineLimit(1)
                    if !nxt.room.isEmpty {
                        Text("  ·  Rm \(nxt.room)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(TertiaryColor.opacity(0.55))
                    }
                    Spacer()
                    Text(nxt.timeRange.components(separatedBy: " to").first ?? "")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(TertiaryColor.opacity(0.6))
                }
                .padding(.horizontal, iPad ? 18 : 14)
                .padding(.vertical, 8)
                .background(TertiaryColor.opacity(0.08))
            }
        }
    }

    // MARK: - Up Next card

    private func upNextCard(_ line: ScheduleLine) -> some View {
        let startSec  = line.startSec ?? 0
        let secsUntil = max(0, startSec - nowSec)
        let minsUntil = secsUntil / 60
        let isSoon    = secsUntil < 600    // < 10 min

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: isSoon ? "bell.fill" : "clock")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TertiaryColor.opacity(0.75))
                    Text(isSoon ? "STARTING SOON" : "UP NEXT")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(TertiaryColor.opacity(0.75))
                        .tracking(1.0)
                }

                Text(displayName(line))
                    .font(.system(size: iPad ? 24 : 18, weight: .black, design: .rounded))
                    .foregroundColor(TertiaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 10) {
                    if !line.room.isEmpty {
                        Label(line.room, systemImage: "mappin.circle.fill")
                            .font(.system(size: iPad ? 13 : 11, weight: .semibold))
                            .foregroundColor(TertiaryColor.opacity(0.8))
                    }
                    Text(line.timeRange)
                        .font(.system(size: iPad ? 12 : 10, weight: .medium, design: .monospaced))
                        .foregroundColor(TertiaryColor.opacity(0.6))
                }
            }

            Spacer()

            // Countdown or start time
            VStack(alignment: .trailing, spacing: 1) {
                if isSoon {
                    if secsUntil > 60 {
                        Text("\(minsUntil)")
                            .font(.system(size: iPad ? 44 : 34, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("MIN")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor.opacity(0.8))
                            .tracking(0.8)
                    } else {
                        Text("\(secsUntil)")
                            .font(.system(size: iPad ? 44 : 34, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("SEC")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(TertiaryColor.opacity(0.8))
                            .tracking(0.8)
                    }
                } else {
                    // Show start time for non-urgent
                    let start = line.timeRange.components(separatedBy: " to").first ?? ""
                    Text(start)
                        .font(.system(size: iPad ? 20 : 16, weight: .bold, design: .monospaced))
                        .foregroundColor(TertiaryColor)
                    Text("START")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(TertiaryColor.opacity(0.55))
                        .tracking(0.8)
                }
            }
        }
        .padding(.horizontal, iPad ? 18 : 14)
        .padding(.vertical, iPad ? 14 : 12)
    }

    // MARK: - Done for today card

    private var doneCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundColor(TertiaryColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Done for today")
                    .font(.system(size: iPad ? 17 : 15, weight: .bold, design: .rounded))
                    .foregroundColor(TertiaryColor)
                Text("No more classes scheduled")
                    .font(.system(size: iPad ? 13 : 11, weight: .medium))
                    .foregroundColor(TertiaryColor.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
