//
//  NewsSourceTabs.swift
//  Schedule
//

import SwiftUI

struct NewsSourceTabs: View {
    @Binding var selectedSource: NewsSource

    let primaryColor: Color
    let secondaryColor: Color
    let tertiaryColor: Color
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NewsSource.allCases) { source in
                Button {
                    guard selectedSource != source else { return }
                    selectedSource = source
                    onSelect()
                } label: {
                    ZStack {
                        buttonBackground(for: source)

                        Text(source.title)
                            .appThemeFont(.secondary, size: iPad ? 15 : 12, weight: .semibold)
                            .lineLimit(iPad ? 1 : 2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(
                                selectedSource == source
                                ? selectedTextColor
                                : primaryColor
                            )
                            .padding(.horizontal, iPad ? 12 : 6)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: iPad ? 46 : 40)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(source.title)
                .accessibilityAddTraits(selectedSource == source ? .isSelected : [])
            }
        }
    }

    private var selectedTextColor: Color {
        usesDarkGraphiteSelection ? primaryColor : tertiaryColor
    }

    private var usesDarkGraphiteSelection: Bool {
        primaryColor.luminance() > 0.7 && tertiaryColor.luminance() < 0.3
    }

    @ViewBuilder
    private func buttonBackground(for source: NewsSource) -> some View {
        let isSelected = selectedSource == source

        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            if isSelected {
                if usesDarkGraphiteSelection {
                    Capsule(style: .continuous)
                        .fill(tertiaryColor.opacity(0.86))
                        .glassEffect(.regular.tint(tertiaryColor.opacity(0.62)))
                } else {
                    Capsule(style: .continuous)
                        .fill(primaryColor.opacity(0.92))
                        .glassEffect()
                }
            } else {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.0001))
                    .glassEffect()
            }
        } else {
            Capsule(style: .continuous)
                .fill(isSelected ? primaryColor : secondaryColor)
        }
    }
}
