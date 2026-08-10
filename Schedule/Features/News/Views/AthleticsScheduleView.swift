//
//  AthleticsScheduleView.swift
//  Schedule
//

import SwiftUI

struct AthleticsScheduleView: View {
    let schedule: AthleticsSchedule
    let primaryColor: Color
    let secondaryColor: Color
    let tertiaryColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            eventSection(title: "Upcoming Games", events: schedule.upcoming, emptyText: "No upcoming games listed.")
            eventSection(title: "Recent Results", events: schedule.recent, emptyText: "No recent results listed.")
        }
    }

    private func eventSection(title: String, events: [AthleticsEvent], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .appThemeFont(.secondary, size: iPad ? 22 : 18, weight: .bold)
                .foregroundStyle(primaryColor)

            if events.isEmpty {
                Text(emptyText)
                    .appThemeFont(.secondary, size: 15, weight: .medium)
                    .foregroundStyle(TertiaryTextColor)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowBackground)
            } else {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        AthleticsEventRow(
                            event: event,
                            primaryColor: primaryColor,
                            tertiaryColor: tertiaryColor
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(secondaryColor)
        )
    }

    private var TertiaryTextColor: Color {
        tertiaryColor.highContrastTextColor()
    }

    private var rowBackground: some ShapeStyle {
        TertiaryTextColor.opacity(0.08)
    }
}

private struct AthleticsEventRow: View {
    let event: AthleticsEvent
    let primaryColor: Color
    let tertiaryColor: Color

    var body: some View {
        Button {
            if let scheduleURL = event.scheduleURL {
                UIApplication.shared.open(scheduleURL)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                dateBlock

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.sportTitle)
                            .appThemeFont(.secondary, size: 15, weight: .bold)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        if let resultText = event.resultText {
                            Text(resultText)
                                .appThemeFont(.secondary, size: 13, weight: .bold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(primaryColor)
                        }
                    }

                    Text(event.matchupText)
                        .appThemeFont(.secondary, size: 14, weight: .semibold)
                        .lineLimit(2)

                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                            .appThemeFont(.secondary, size: 13, weight: .medium)
                            .lineLimit(2)
                            .foregroundStyle(textColor.opacity(0.78))
                    }
                }
                .foregroundStyle(textColor)

                if event.scheduleURL != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(textColor.opacity(0.45))
                        .padding(.top, 4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(textColor.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(event.scheduleURL == nil)
    }

    private var dateBlock: some View {
        VStack(spacing: 4) {
            Text(event.dateText)
                .appThemeFont(.secondary, size: 13, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(event.timeText)
                .appThemeFont(.secondary, size: 12, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .frame(width: iPad ? 82 : 68)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(primaryColor)
        )
    }

    private var textColor: Color {
        tertiaryColor.highContrastTextColor()
    }
}

#if DEBUG
#Preview("Athletics Schedule") {
    AthleticsScheduleView(
        schedule: AthleticsSchedule(
            upcoming: [
                AthleticsEvent(
                    id: 1,
                    date: Date(),
                    dateText: "May 14",
                    time: "3:30 PM",
                    sportTitle: "Men's Varsity Lacrosse",
                    opponentTitle: "CCS Semis Saint Ignatius HS",
                    location: "Saint Ignatius HS",
                    locationIndicator: "A",
                    resultStatus: nil,
                    teamScore: nil,
                    opponentScore: nil,
                    scheduleURL: URL(string: "https://sfhsathletics.com"),
                    isTBD: false
                )
            ],
            recent: [
                AthleticsEvent(
                    id: 2,
                    date: Date(),
                    dateText: "May 13",
                    time: "4:00 PM",
                    sportTitle: "Varsity Softball",
                    opponentTitle: "Sacred Heart Cathedral HS",
                    location: "Saint Francis HS",
                    locationIndicator: "H",
                    resultStatus: "W",
                    teamScore: "12",
                    opponentScore: "0",
                    scheduleURL: URL(string: "https://sfhsathletics.com"),
                    isTBD: false
                )
            ]
        ),
        primaryColor: .blue,
        secondaryColor: .blue.opacity(0.12),
        tertiaryColor: .white
    )
    .padding()
}
#endif
