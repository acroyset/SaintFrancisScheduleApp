//
//  TutorialView.swift
//  Schedule
//

import SwiftUI

// MARK: - Step model

private struct TutorialStep {
    let state: TutorialState
    let title: String
    let body:  String
}

private let steps: [TutorialStep] = [
    TutorialStep(
        state: .Intro,
        title: "Welcome to Schedule!",
        body: "This quick tour shows you around the app. Use the Next button to walk through each feature."
    ),
    TutorialStep(
        state: .DateNavigator,
        title: "Date Navigator",
        body: "Tap the date at the top to open a full calendar. Jump to any day of the school year to see its schedule, or swipe left and right on the main screen to move between days."
    ),
    TutorialStep(
        state: .News,
        title: "News Tab",
        body: "Tap the newspaper icon in the toolbar to read Saint Francis news — clubs, games, events, and announcements."
    ),
    TutorialStep(
        state: .ClassesView,
        title: "Classes Tab",
        body: "Tap the clipboard icon to edit your class names, teacher, and room — and toggle second lunch."
    ),
    TutorialStep(
        state: .Settings,
        title: "Profile & Settings",
        body: "Tap the person icon to open your profile. Inside, tap the gear to change your color theme and notification time."
    ),
    TutorialStep(
        state: .Outro,
        title: "You're all set! 🎉",
        body: "You can restart this tutorial anytime from your Profile tab. Good luck this school year!"
    ),
]

// MARK: - TutorialView

struct TutorialView: View {
    @Binding var tutorial: TutorialState
    let PrimaryColor:  Color
    let TertiaryColor: Color
    var onStart: (() -> Void)? = nil

    @State private var cardAppeared = false

    private var stepIndex: Int? { steps.firstIndex { $0.state == tutorial } }
    private var currentStep: TutorialStep? { stepIndex.map { steps[$0] } }

    var body: some View {
        if let step = currentStep {
            ZStack {
                cardView(step: step)
                    .scaleEffect(cardAppeared ? 1 : 0.92)
                    .opacity(cardAppeared ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .id(tutorial)
            .onAppear {
                animateIn()
                if tutorial == .Intro { onStart?() }
            }
            .onChange(of: tutorial) { _, newState in
                animateIn()
                if newState == .Intro { onStart?() }
            }
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func cardView(step: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 20) {

            // Progress dots + counter
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    let active = steps[i].state == tutorial
                    Circle()
                        .fill(active ? PrimaryColor : PrimaryColor.opacity(0.2))
                        .frame(width: active ? 9 : 6, height: active ? 9 : 6)
                        .animation(.spring(response: 0.25), value: tutorial)
                }
                Spacer()
                if let i = stepIndex {
                    Text("\(i + 1) / \(steps.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Title
            Text(step.title)
                .font(.system(size: iPad ? 26 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(PrimaryColor)

            // Body
            Text(step.body)
                .font(.system(size: iPad ? 17 : 15))
                .foregroundStyle(TertiaryColor.highContrastTextColor())
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            // Help link — pill background ensures it's readable on any card colour
            HStack(spacing: 4) {
                Text("Need more help?")
                    .font(.caption)
                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                Button("Visit our website") {
                    UIApplication.shared.open(
                        URL(string: "https://sites.google.com/view/sf-schedule-help/home")!
                    )
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrimaryColor)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PrimaryColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Navigation buttons
            HStack {
                if let i = stepIndex, i > 0 {
                    Button(action: navigateBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PrimaryColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
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
                    .foregroundStyle(TertiaryColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(PrimaryColor)
                    .clipShape(Capsule())
                    .shadow(color: PrimaryColor.opacity(0.4), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        .frame(maxWidth: iPad ? 460 : 320)
        .padding(.horizontal, 24)
    }

    // MARK: - Navigation

    private func navigateForward() {
        guard let i = stepIndex else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            tutorial = i < steps.count - 1 ? steps[i + 1].state : .Hidden
        }
    }

    private func navigateBack() {
        guard let i = stepIndex, i > 0 else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            tutorial = steps[i - 1].state
        }
    }

    private func animateIn() {
        cardAppeared = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            cardAppeared = true
        }
    }
}
