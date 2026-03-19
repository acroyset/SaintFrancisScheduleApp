//
//  OnboardingView.swift
//  Schedule
//
//  Created by Andreas Royset on 3/19/26.
//
//
//  Shown once after a user's first sign-in.
//  Lets them fill in their 7 class names before entering the app.
//  Stored in UserDefaults so it never shows again after completion or skip.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    // Passed in so we can write back to the app's live data
    var onComplete: ([String]) -> Void

    @State private var classNames: [String] = Array(repeating: "", count: 7)
    @State private var currentStep = 0   // which class we're focused on

    private let placeholders = [
        "Period 1 — e.g. AP Biology",
        "Period 2 — e.g. English 2 Honors",
        "Period 3 — e.g. Algebra 2",
        "Period 4 — e.g. US History",
        "Period 5 — e.g. Spanish 3",
        "Period 6 — e.g. Chemistry",
        "Period 7 — e.g. PE / Elective"
    ]

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                    .padding(.top, 8)

                Text("Set Up Your Classes")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Enter your class names so your schedule shows the right subjects. You can always edit them later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // ── Class fields ──────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { i in
                        ClassNameRow(
                            index: i,
                            text: $classNames[i],
                            placeholder: placeholders[i],
                            isFocused: currentStep == i,
                            onSubmit: {
                                // Advance to next field on Return
                                if i < 6 { currentStep = i + 1 }
                                else { currentStep = -1 }  // dismiss keyboard
                            }
                        )
                        .onTapGesture { currentStep = i }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()

            // ── Action buttons ────────────────────────────────────────────
            VStack(spacing: 10) {
                Button {
                    saveAndEnter()
                } label: {
                    Text(hasAnyName ? "Save & Enter App" : "Enter App")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    skip()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20)
        .padding(.horizontal, 20)
        .onAppear {
            // Auto-focus first field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                currentStep = 0
            }
        }
    }

    // MARK: - Helpers

    private var hasAnyName: Bool {
        classNames.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func saveAndEnter() {
        let trimmed = classNames.map { $0.trimmingCharacters(in: .whitespaces) }
        onComplete(trimmed)
        markOnboardingDone()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func skip() {
        onComplete([])
        markOnboardingDone()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func markOnboardingDone() {
        UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
    }
}

// MARK: - Single row

private struct ClassNameRow: View {
    let index: Int
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Period badge
            Text("P\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(isFocused ? .white : .blue)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.blue : Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .submitLabel(index < 6 ? .next : .done)
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFocused
                      ? Color.blue.opacity(0.06)
                      : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .onChange(of: isFocused) { _, newVal in
            if newVal { focused = true }
        }
        .onAppear {
            if isFocused { focused = true }
        }
    }
}
