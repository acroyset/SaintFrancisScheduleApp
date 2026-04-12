//
//  LancerLiveVideoCard.swift
//  Schedule
//

import SwiftUI

struct LancerLiveVideoCard: View {
    let video: LancerLiveVideo
    let primaryColor: Color
    let secondaryColor: Color
    let tertiaryColor: Color
    let onFullscreen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onFullscreen) {
                ZStack {
                    Rectangle()
                        .fill(secondaryColor)

                    AsyncImage(url: video.thumbnailURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(1.08)
                            .offset(y: -10)
                    } placeholder: {
                        ProgressView()
                            .tint(primaryColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                .mask(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay(alignment: .center) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: iPad ? 72 : 56))
                        .foregroundStyle(.white)
                        .shadow(radius: 12)
                }
            }
            .buttonStyle(.plain)

            Text("Latest from Lancer Live")
                .appThemeFont(.secondary, size: 14, weight: .semibold)
                .foregroundStyle(primaryColor.opacity(0.8))

            Text(video.title)
                .appThemeFont(.primary, size: iPad ? 28 : 22, weight: .bold)
                .foregroundStyle(tertiaryColor.highContrastTextColor())

            Text("Published \(video.publishedText)")
                .appThemeFont(.secondary, size: 14, weight: .medium)
                .foregroundStyle(tertiaryColor.highContrastTextColor().opacity(0.7))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(secondaryColor)
        )
    }
}
