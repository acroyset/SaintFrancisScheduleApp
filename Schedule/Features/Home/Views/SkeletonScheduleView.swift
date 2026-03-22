//
//  SkeletonScheduleView.swift
//  Schedule
//
//  Created by Andreas Royset on 3/19/26.
//
//
//  Shown in place of the schedule list while the CSV is still loading.
//  Cards shuffle up and down slightly to give a "thinking" feel.
//

import SwiftUI

struct SkeletonScheduleView: View {
    let PrimaryColor: Color
    let SecondaryColor: Color

    // Staggered vertical offsets, one per card
    @State private var offsets: [CGFloat] = Array(repeating: 0, count: 6)
    @State private var opacities: [Double] = Array(repeating: 0.5, count: 6)

    private let cardHeights: [CGFloat] = [56, 52, 64, 52, 56, 60]
    private let widths: [CGFloat] = [0.75, 0.55, 0.65, 0.5, 0.7, 0.6]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { i in
                skeletonCard(index: i)
            }
        }
        .padding(.horizontal, 12)
        .onAppear { startAnimating() }
    }

    @ViewBuilder
    private func skeletonCard(index: Int) -> some View {
        HStack(spacing: 12) {
            // Progress bar placeholder
            RoundedRectangle(cornerRadius: 3)
                .fill(PrimaryColor.opacity(0.15))
                .frame(width: 6, height: cardHeights[index] - 16)

            VStack(alignment: .leading, spacing: 8) {
                // Time range placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(PrimaryColor.opacity(0.12))
                    .frame(width: 90, height: 10)

                // Class name placeholder — varied widths
                RoundedRectangle(cornerRadius: 4)
                    .fill(PrimaryColor.opacity(0.18))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                    .padding(.trailing, 40 + CGFloat(index % 3) * 20)

                // Teacher / room placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(PrimaryColor.opacity(0.10))
                    .frame(width: 120, height: 9)
            }

            Spacer()
        }
        .padding(12)
        .frame(height: cardHeights[index])
        .background(SecondaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .offset(y: offsets[index])
        .opacity(opacities[index])
    }

    private func startAnimating() {
        for i in 0..<6 {
            let delay = Double(i) * 0.12
            animateCard(index: i, delay: delay)
        }
    }

    private func animateCard(index: Int, delay: Double) {
        let duration = 0.9 + Double(index % 3) * 0.15
        let targetOffset: CGFloat = index % 2 == 0 ? -5 : 5
        let targetOpacity: Double = index % 2 == 0 ? 0.75 : 0.45

        withAnimation(
            Animation
                .easeInOut(duration: duration)
                .delay(delay)
                .repeatForever(autoreverses: true)
        ) {
            offsets[index] = targetOffset
            opacities[index] = targetOpacity
        }
    }
}
