//
//  DayHeaderView.swift
//  Schedule
import SwiftUI

struct DayHeaderView: View {
    let dayInfo: Day?
    let dayCode: String
    let isToday: Bool
    let PrimaryColor:   Color
    let SecondaryColor: Color
    let TertiaryColor:  Color

    // MARK: - Derived

    private var dayName: String { dayInfo?.name ?? "No Classes" }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {

                // Main day name
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    Text(dayName)
                        .appThemeFont(.primary, size: iPad ? 52 : 32, weight: .black)
                        .foregroundColor(TertiaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(dayName)
                        .appThemeFont(.primary, size: iPad ? 52 : 32, weight: .black)
                        .foregroundColor(PrimaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, iPad ? 20 : 16)
            .padding(.vertical, iPad ? 12 : 10)
            
            Spacer()

            if isToday {
                todayBadge
                    .padding(.trailing, iPad ? 20 : 16)
            }
        }
    }

    @ViewBuilder
    private var todayBadge: some View {
        let labelColor = isLiquidGlassStyle ? TertiaryColor : PrimaryColor
        let badgeBackground = isLiquidGlassStyle
            ? TertiaryColor.opacity(0.16)
            : SecondaryColor.opacity(0.95)

        HStack(spacing: 6) {
            Image(systemName: "smallcircle.fill.circle")
                .font(.system(size: iPad ? 12 : 10, weight: .bold))
            Text("Today")
                .appThemeFont(.secondary, size: iPad ? 16 : 13, weight: .semibold)
        }
        .foregroundColor(labelColor)
        .padding(.horizontal, iPad ? 14 : 12)
        .padding(.vertical, iPad ? 10 : 8)
        .background(
            Capsule()
                .fill(badgeBackground)
        )
    }

    private var isLiquidGlassStyle: Bool {
        if #available(iOS 26.0, *) {
            return AppAvailability.liquidGlass
        }
        return false
    }
}
