//
//  TutorialView.swift
//  Schedule
//
//  Arrow-overlay tutorial that points to real UI elements.
//  Fixes:
//  • Backdrop tap does NOT advance/close — only the Next/Done buttons do.
//    This prevents ContentView's background .onTapGesture from closing it early.
//  • Navigation uses array index arithmetic, never rawValue, so Hidden (0)
//    can never be reached accidentally mid-tour.
//

import SwiftUI

// MARK: - Step model

private struct TutorialStep {
    let state:       TutorialState
    let title:       String
    let body:        String
    /// Normalised (0–1) screen position for the animated arrow tip. nil = no arrow.
    let arrowTarget: UnitPoint?
    /// Where the callout card anchors on screen.
    let cardAnchor:  Alignment
}

private let steps: [TutorialStep] = [
    TutorialStep(
        state: .Intro,
        title: "Welcome to Schedule!",
        body: "This quick tour shows you around the app. Use the Next button to walk through each feature.",
        arrowTarget: nil,
        cardAnchor: .center
    ),
    TutorialStep(
        state: .DateNavigator,
        title: "Date Navigator",
        body: "Tap the date shown here to open the calendar and jump to any day of the school year.",
        arrowTarget: UnitPoint(x: 0.5, y: 0.25),
        cardAnchor: .bottom
    ),
    TutorialStep(
        state: .News,
        title: "News Tab",
        body: "Tap the newspaper icon to read Saint Francis news — clubs, games, events, and announcements.",
        arrowTarget: UnitPoint(x: 0.30, y: 0.955),
        cardAnchor: .top
    ),
    TutorialStep(
        state: .ClassesView,
        title: "Classes Tab",
        body: "Tap the clipboard icon to edit your class names, teacher, and room — and toggle second lunch.",
        arrowTarget: UnitPoint(x: 0.57, y: 0.955),
        cardAnchor: .top
    ),
    TutorialStep(
        state: .Settings,
        title: "Profile & Settings",
        body: "Tap the person icon, then the gear inside, to change your color theme and notification time.",
        arrowTarget: UnitPoint(x: 0.84, y: 0.955),
        cardAnchor: .top
    ),
    TutorialStep(
        state: .Outro,
        title: "You're all set! 🎉",
        body: "You can restart this tutorial anytime from your Profile tab. Good luck this school year!",
        arrowTarget: nil,
        cardAnchor: .center
    ),
]

// MARK: - TutorialView

struct TutorialView: View {
    @Binding var tutorial: TutorialState
    let PrimaryColor:  Color
    let TertiaryColor: Color

    @State private var arrowBounce:  CGFloat = 0
    @State private var cardAppeared: Bool    = false

    private var stepIndex: Int? { steps.firstIndex { $0.state == tutorial } }
    private var currentStep: TutorialStep? { stepIndex.map { steps[$0] } }

    var body: some View {
        GeometryReader { geo in
            if let step = currentStep {
                ZStack {
                    // ── Dimming backdrop — blocks ALL taps from reaching views behind ──
                    Color.black.opacity(0.60)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { /* intentionally empty: swallow tap */ }

                    // ── Animated arrow ──────────────────────────────────────────────
                    if let target = step.arrowTarget {
                        arrowStack(target: target, size: geo.size)
                            .allowsHitTesting(false)
                    }

                    // ── Callout card ────────────────────────────────────────────────
                    cardView(step: step, geo: geo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: step.cardAnchor)
                        .padding(cardInsets(step: step, geo: geo))
                        .scaleEffect(cardAppeared ? 1 : 0.90)
                        .opacity(cardAppeared ? 1 : 0)
                }
                .id(tutorial) // force full redraw between steps
                .onAppear { animateIn() }
                .onChange(of: tutorial) { _, _ in animateIn() }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Arrow

    @ViewBuilder
    private func arrowStack(target: UnitPoint, size: CGSize) -> some View {
        let tipX      = target.x * size.width
        let tipY      = target.y * size.height
        let pointDown = target.y > 0.6   // near toolbar → arrow points down toward it

        VStack(spacing: -8) {
            if pointDown {
                chevron("chevron.compact.down", opacity: 0.4)
                chevron("chevron.compact.down", opacity: 1.0)
            } else {
                chevron("chevron.compact.up", opacity: 1.0)
                chevron("chevron.compact.up", opacity: 0.4)
            }
        }
        .offset(
            x: tipX - 20,
            y: pointDown
                ? tipY - 76 - arrowBounce
                : tipY + 16 + arrowBounce
        )
    }

    private func chevron(_ name: String, opacity: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(PrimaryColor.opacity(opacity))
            .shadow(color: .black.opacity(0.45), radius: 3)
    }

    // MARK: Card

    @ViewBuilder
    private func cardView(step: TutorialStep, geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            // Progress dots + counter
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    let active = steps[i].state == tutorial
                    Circle()
                        .fill(active ? PrimaryColor : PrimaryColor.opacity(0.22))
                        .frame(width: active ? 9 : 6, height: active ? 9 : 6)
                        .animation(.spring(response: 0.25), value: tutorial)
                }
                Spacer()
                if let i = stepIndex {
                    Text("\(i + 1) / \(steps.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Title
            Text(step.title)
                .font(.system(size: iPad ? 26 : 20, weight: .bold, design: .rounded))
                .foregroundColor(PrimaryColor)

            // Body
            Text(step.body)
                .font(.system(size: iPad ? 17 : 15))
                .foregroundColor(TertiaryColor.highContrastTextColor())
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            // Support link
            HStack(spacing: 4) {
                Text("Need more help?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Visit our website") {
                    UIApplication.shared.open(
                        URL(string: "https://sites.google.com/view/sf-schedule-help/home")!
                    )
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            // Back / Next
            HStack {
                if let i = stepIndex, i > 0 {
                    Button(action: navigateBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PrimaryColor)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(PrimaryColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: navigateForward) {
                    HStack(spacing: 5) {
                        Text(tutorial == .Outro ? "Done" : "Next")
                        if tutorial != .Outro {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TertiaryColor)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(PrimaryColor)
                    .clipShape(Capsule())
                    .shadow(color: PrimaryColor.opacity(0.4), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(TertiaryColor)
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        )
        .frame(maxWidth: iPad ? 460 : 320)
    }

    // MARK: Navigation

    private func navigateForward() {
        guard let i = stepIndex else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            if i < steps.count - 1 {
                tutorial = steps[i + 1].state
            } else {
                tutorial = .Hidden
            }
        }
    }

    private func navigateBack() {
        guard let i = stepIndex, i > 0 else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            tutorial = steps[i - 1].state
        }
    }

    // MARK: Animation

    private func animateIn() {
        cardAppeared = false
        arrowBounce  = 0
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            cardAppeared = true
        }
        withAnimation(
            .easeInOut(duration: 0.52)
            .repeatForever(autoreverses: true)
            .delay(0.25)
        ) {
            arrowBounce = 10
        }
    }

    private func cardInsets(step: TutorialStep, geo: GeometryProxy) -> EdgeInsets {
        let h: CGFloat = 20
        switch step.cardAnchor {
        case .bottom:
            return EdgeInsets(top: 0, leading: h, bottom: geo.size.height * 0.15, trailing: h)
        case .top:
            return EdgeInsets(top: geo.size.height * 0.10, leading: h, bottom: 0, trailing: h)
        default:
            return EdgeInsets(top: 0, leading: h, bottom: 0, trailing: h)
        }
    }
}
