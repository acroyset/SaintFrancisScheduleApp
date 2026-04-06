//
//  DayHeaderView.swift
//  Schedule
import SwiftUI

struct DayHeaderView: View {
    let dayInfo: Day?
    let dayCode: String
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
        }
    }
}
