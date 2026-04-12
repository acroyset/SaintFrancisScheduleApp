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
                            .appThemeFont(.secondary, size: iPad ? 15 : 13, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(
                                selectedSource == source
                                ? Color.white
                                : tertiaryColor.highContrastTextColor()
                            )
                            .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: iPad ? 46 : 40)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func buttonBackground(for source: NewsSource) -> some View {
        let isSelected = selectedSource == source

        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(primaryColor.opacity(0.92))
                    .glassEffect()
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
