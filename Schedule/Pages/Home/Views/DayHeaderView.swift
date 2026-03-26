//
//  DayHeaderView.swift
//  Schedule
//
//  Updated to make rotation day immediately obvious.
//  Unusual days (Activity, Liturgy, Special) get an extra visual cue
//  so users can never miss an off-schedule day.
//

import SwiftUI

struct DayHeaderView: View {
    let dayInfo: Day?
    let dayCode: String
    let PrimaryColor:   Color
    let SecondaryColor: Color
    let TertiaryColor:  Color

    // MARK: - Derived

    private var dayName: String { dayInfo?.name ?? "No Classes" }

    /// True for anything that's not a standard Gold/Brown day
    private var isUnusualDay: Bool {
        let n = dayName.lowercased()
        return n.contains("activity") || n.contains("liturgy") ||
               n.contains("special")  || n.contains("no class")
    }

    private var unusualLabel: String {
        let n = dayName.lowercased()
        if n.contains("activity") { return "MODIFIED SCHEDULE" }
        if n.contains("liturgy")  { return "MODIFIED SCHEDULE" }
        if n.contains("special")  { return "UNUSUAL SCHEDULE" }
        return "CHECK SCHEDULE"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {

                // Main day name
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    Text(dayName)
                        .font(.system(size: iPad ? 52 : 32, weight: .black))
                        .foregroundColor(TertiaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(dayName)
                        .font(.system(size: iPad ? 52 : 32, weight: .black))
                        .foregroundColor(PrimaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, iPad ? 20 : 16)
            .padding(.vertical, iPad ? 12 : 10)

            Spacer()

            // Unusual day warning badge
            if isUnusualDay {
                unusualBadge
                    .padding(.trailing, iPad ? 20 : 16)
            }
        }
    }

    // MARK: - Unusual day badge

    private var unusualBadge: some View {
        VStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: iPad ? 18 : 14))
                .foregroundColor(.orange)

            Text(unusualLabel)
                .font(.system(size: iPad ? 9 : 7, weight: .black, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var headerForeground: Color {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            return TertiaryColor
        }
        return PrimaryColor
    }
}
