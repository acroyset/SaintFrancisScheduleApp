//
//  NowNextCard.swift
//  Schedule
//
//  Fix: All card variants now explicitly use PrimaryColor as background
//  so the card always matches the header pill color.
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
    let cornerRadius: CGFloat
    let usesGlassStyle: Bool

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

    var body: some View {
        Group {
            if !isToday {
                EmptyView()
            } else if isDoneForDay {
                doneCard
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if let cur = currentClass {
                inClassCard(cur)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if let nxt = nextClass {
                upNextCard(nxt)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private var cardBackground: Color {
        usesGlassStyle ? .clear : PrimaryColor.opacity(0.9)
    }

    // MARK: - In Class card

    private func inClassCard(_ line: ScheduleLine) -> some View {
        let secsLeft   = max(0, (line.endSec ?? nowSec) - nowSec)
        let minsLeft   = secsLeft / 60
        let progress   = line.progress ?? 0

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(TertiaryColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: TertiaryColor.opacity(0.6), radius: 4)
                        Text("IN CLASS")
                            .appThemeFont(.secondary, size: 10, weight: .black)
                            .foregroundColor(TertiaryColor.opacity(0.8))
                            .tracking(1.2)
                    }

                    Text(displayName(line))
                        .appThemeFont(.primary, size: iPad ? 26 : 20, weight: .black)
                        .foregroundColor(TertiaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 10) {
                        if !line.room.isEmpty {
                            Label(line.room, systemImage: "mappin.circle.fill")
                                .appThemeFont(.primary, size: iPad ? 13 : 11, weight: .semibold)
                                .foregroundColor(TertiaryColor.opacity(0.85))
                        }
                        if !line.teacher.isEmpty {
                            Text(line.teacher)
                                .appThemeFont(.primary, size: iPad ? 12 : 10, weight: .medium)
                                .foregroundColor(TertiaryColor.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    if secsLeft < 60 {
                        Text("\(secsLeft)")
                            .appThemeFont(.secondary, size: iPad ? 48 : 38, weight: .black)
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("SEC LEFT")
                            .appThemeFont(.secondary, size: 8, weight: .black)
                            .foregroundColor(TertiaryColor.opacity(0.85))
                            .tracking(0.8)
                    } else {
                        Text("\(minsLeft)")
                            .appThemeFont(.secondary, size: iPad ? 48 : 38, weight: .black)
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("MIN LEFT")
                            .appThemeFont(.secondary, size: 8, weight: .black)
                            .foregroundColor(TertiaryColor.opacity(0.75))
                            .tracking(0.8)
                    }
                }
            }
            .padding(.horizontal, iPad ? 18 : 14)
            .padding(.top, iPad ? 14 : 12)
            .padding(.bottom, 10)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TertiaryColor.opacity(0.15))
                    Rectangle()
                        .fill(TertiaryColor.opacity(0.4))
                        .frame(width: geo.size.width * CGFloat(progress))
                        .animation(.linear(duration: 0.5), value: progress)
                }
            }
            .frame(height: 3)

            // Next class footer
            if let nxt = nextClass {
                HStack(spacing: 0) {
                    Text("NEXT ")
                        .appThemeFont(.secondary, size: 10, weight: .black)
                        .foregroundColor(TertiaryColor.opacity(0.5))
                        .tracking(0.5)
                    Text(displayName(nxt))
                        .appThemeFont(.secondary, size: 10, weight: .bold)
                        .foregroundColor(TertiaryColor.opacity(0.75))
                        .lineLimit(1)
                    if !nxt.room.isEmpty {
                        Text("  ·  Rm \(nxt.room)")
                            .appThemeFont(.secondary, size: 10, weight: .medium)
                            .foregroundColor(TertiaryColor.opacity(0.55))
                    }
                    Spacer()
                    Text(nxt.timeRange.components(separatedBy: " to").first ?? "")
                        .appThemeFont(.secondary, size: 10, weight: .semibold)
                        .foregroundColor(TertiaryColor.opacity(0.6))
                }
                .padding(.horizontal, iPad ? 18 : 14)
                .padding(.vertical, 8)
                .background(usesGlassStyle ? Color.clear : TertiaryColor.opacity(0.08))
            }
        }
    }

    // MARK: - Up Next card

    private func upNextCard(_ line: ScheduleLine) -> some View {
        let startSec  = line.startSec ?? 0
        let secsUntil = max(0, startSec - nowSec)
        let minsUntil = secsUntil / 60
        let isSoon    = secsUntil < 600

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: isSoon ? "bell.fill" : "clock")
                        .appThemeFont(.primary, size: 9, weight: .bold)
                        .foregroundColor(TertiaryColor.opacity(0.75))
                    Text(isSoon ? "STARTING SOON" : "UP NEXT")
                        .appThemeFont(.secondary, size: 10, weight: .black)
                        .foregroundColor(TertiaryColor.opacity(0.75))
                        .tracking(1.0)
                }

                Text(displayName(line))
                    .appThemeFont(.primary, size: iPad ? 24 : 18, weight: .black)
                    .foregroundColor(TertiaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 10) {
                    if !line.room.isEmpty {
                        Label(line.room, systemImage: "mappin.circle.fill")
                            .appThemeFont(.primary, size: iPad ? 13 : 11, weight: .semibold)
                            .foregroundColor(TertiaryColor.opacity(0.8))
                    }
                    Text(line.timeRange)
                        .appThemeFont(.secondary, size: iPad ? 12 : 10, weight: .medium)
                        .foregroundColor(TertiaryColor.opacity(0.6))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                if isSoon {
                    if secsUntil > 60 {
                        Text("\(minsUntil)")
                            .appThemeFont(.secondary, size: iPad ? 44 : 34, weight: .black)
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("MIN")
                            .appThemeFont(.secondary, size: 8, weight: .black)
                            .foregroundColor(TertiaryColor.opacity(0.8))
                            .tracking(0.8)
                    } else {
                        Text("\(secsUntil)")
                            .appThemeFont(.secondary, size: iPad ? 44 : 34, weight: .black)
                            .foregroundColor(TertiaryColor)
                            .contentTransition(.numericText())
                        Text("SEC")
                            .appThemeFont(.secondary, size: 8, weight: .black)
                            .foregroundColor(TertiaryColor.opacity(0.8))
                            .tracking(0.8)
                    }
                } else {
                    let start = line.timeRange.components(separatedBy: " to").first ?? ""
                    Text(start)
                        .appThemeFont(.secondary, size: iPad ? 20 : 16, weight: .bold)
                        .foregroundColor(TertiaryColor)
                    Text("START")
                        .appThemeFont(.secondary, size: 8, weight: .black)
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
                .appThemeFont(.primary, size: 26)
                .foregroundColor(TertiaryColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Done for today")
                    .appThemeFont(.primary, size: iPad ? 17 : 15, weight: .bold)
                    .foregroundColor(TertiaryColor)
                Text("No more classes scheduled")
                    .appThemeFont(.primary, size: iPad ? 13 : 11, weight: .medium)
                    .foregroundColor(TertiaryColor.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
