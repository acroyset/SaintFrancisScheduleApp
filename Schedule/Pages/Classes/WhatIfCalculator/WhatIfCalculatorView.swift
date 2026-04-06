//
//  WhatIfCalculatorView.swift
//  Schedule
//

import SwiftUI

struct WhatIfGradeCalculatorModal: View {
    private enum WhatIfMode: String, CaseIterable, Identifiable {
        case weightedCategory = "Weighted Categories"
        case pointsBased = "Points Based"

        var id: String { rawValue }
    }

    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var window: classWindow

    @State private var mode: WhatIfMode = .weightedCategory
    @State private var selectedClassIndex: Int = 0
    @State private var currentGrade: String = "90"
    @State private var hypotheticalScore: String = "100"
    @State private var categoryGrade: String = "88"
    @State private var categoryWeight: String = "30"
    @State private var assignmentWeightInCategory: String = "20"
    @State private var currentPointsEarned: String = "180"
    @State private var currentPointsPossible: String = "200"
    @State private var assignmentPointsPossible: String = "20"

    private var classOptions: [(index: Int, name: String)] {
        data.classes.enumerated().compactMap { index, item in
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard index < 7, !trimmed.isEmpty, trimmed != "None", trimmed != "Period \(index + 1)" else { return nil }
            return (index, trimmed)
        }
    }

    private var result: (newGrade: Double, delta: Double)? {
        switch mode {
        case .weightedCategory:
            guard let current = Double(currentGrade),
                  let categoryCurrent = Double(categoryGrade),
                  let categoryWeightValue = Double(categoryWeight),
                  let assignmentWeightValue = Double(assignmentWeightInCategory),
                  let score = Double(hypotheticalScore),
                  (0...100).contains(current),
                  (0...100).contains(categoryCurrent),
                  (0...100).contains(categoryWeightValue),
                  (0...100).contains(assignmentWeightValue),
                  (0...100).contains(score),
                  categoryWeightValue > 0,
                  assignmentWeightValue > 0,
                  assignmentWeightValue < 100 else {
                return nil
            }

            let updatedCategoryGrade =
                categoryCurrent * (1 - assignmentWeightValue / 100) +
                score * (assignmentWeightValue / 100)

            let newGrade =
                current +
                (updatedCategoryGrade - categoryCurrent) * (categoryWeightValue / 100)

            return (newGrade, newGrade - current)

        case .pointsBased:
            guard let current = Double(currentGrade),
                  let earned = Double(currentPointsEarned),
                  let possible = Double(currentPointsPossible),
                  let assignmentPossible = Double(assignmentPointsPossible),
                  let score = Double(hypotheticalScore),
                  (0...100).contains(current),
                  earned >= 0,
                  possible > 0,
                  assignmentPossible > 0,
                  (0...100).contains(score),
                  earned <= possible else {
                return nil
            }

            let earnedOnAssignment = assignmentPossible * (score / 100)
            let updatedCategoryGrade = ((earned + earnedOnAssignment) / (possible + assignmentPossible)) * 100
            return (updatedCategoryGrade, updatedCategoryGrade - current)
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 12) {
                    Color.clear.frame(height: iPad ? 90 : 80)

                    infoCard(
                        title: "Class",
                        subtitle: "Pick the class you want to test."
                    ) {
                        Picker("Class", selection: $selectedClassIndex) {
                            if classOptions.isEmpty {
                                Text("No classes yet").tag(0)
                            } else {
                                ForEach(classOptions, id: \.index) { option in
                                    Text(option.name).tag(option.index)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(PrimaryColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    infoCard(
                        title: "Current Grade",
                        subtitle: "Your current overall class grade."
                    ) {
                        percentageField(text: $currentGrade, placeholder: "90")
                    }

                    infoCard(
                        title: "Mode",
                        subtitle: "Choose how your teacher calculates grades."
                    ) {
                        Picker("Mode", selection: $mode) {
                            ForEach(WhatIfMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(PrimaryColor)
                    }

                    if mode == .weightedCategory {
                        infoCard(
                            title: "Category Grade",
                            subtitle: "Your current grade inside that category."
                        ) {
                            percentageField(text: $categoryGrade, placeholder: "88")
                        }

                        infoCard(
                            title: "Category Weight",
                            subtitle: "How much that category counts toward the class grade."
                        ) {
                            percentageField(text: $categoryWeight, placeholder: "30")
                        }

                        infoCard(
                            title: "Assignment Weight In Category",
                            subtitle: "How much this assignment affects that category."
                        ) {
                            percentageField(text: $assignmentWeightInCategory, placeholder: "20")
                        }
                    } else {
                        infoCard(
                            title: "Current Points",
                            subtitle: "Enter the points you have so far in this class or category."
                        ) {
                            VStack(spacing: 8) {
                                pointField(
                                    title: "Points Earned",
                                    text: $currentPointsEarned,
                                    placeholder: "180"
                                )
                                pointField(
                                    title: "Points Possible",
                                    text: $currentPointsPossible,
                                    placeholder: "200"
                                )
                            }
                        }

                        infoCard(
                            title: "Assignment Size",
                            subtitle: "How many total points this assignment is worth."
                        ) {
                            pointField(
                                title: "Assignment Points",
                                text: $assignmentPointsPossible,
                                placeholder: "20"
                            )
                        }
                    }

                    infoCard(
                        title: "What If I Get...",
                        subtitle: "The score you want to test on that assignment."
                    ) {
                        percentageField(text: $hypotheticalScore, placeholder: "100")
                    }

                    if let result {
                        VStack(spacing: 12) {
                            HStack {
                                Text(currentClassName)
                                    .appThemeFont(.secondary, size: 14, weight: .semibold)
                                    .foregroundStyle(PrimaryColor)
                                Spacer()
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(PrimaryColor)

                                VStack(spacing: 6) {
                                    Text(String(format: "%.2f%%", result.newGrade))
                                        .appThemeFont(.primary, size: 32, weight: .bold)
                                        .foregroundStyle(TertiaryColor)
                                    Text(deltaText(result.delta))
                                        .appThemeFont(.secondary, size: 12, weight: .semibold)
                                        .foregroundStyle(TertiaryColor.opacity(0.85))
                                }
                                .padding(18)
                            }
                            .frame(minHeight: 88)

                            Text(resultDescription)
                                .appThemeFont(.secondary, size: 12, weight: .medium)
                                .foregroundStyle(TertiaryColor.highContrastTextColor())
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                        .background(SecondaryColor)
                        .cornerRadius(12)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .appThemeFont(.primary, size: 24)
                                .foregroundStyle(PrimaryColor.opacity(0.5))

                            Text("Enter valid percentages to preview the grade change")
                                .appThemeFont(.secondary, size: 12, weight: .semibold)
                                .foregroundStyle(PrimaryColor.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(SecondaryColor)
                        .cornerRadius(12)
                    }
                }
                .padding(16)

                Color.clear.frame(height: iPad ? 60 : 50)
            }
            .onTapGesture { hideKeyboard() }
            .mask {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack {
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    HStack {
                        Text("What-If Calculator")
                            .appThemeFont(.secondary, size: iPad ? 34 : 18, weight: .bold)
                            .padding(iPad ? 16 : 12)
                            .padding(.horizontal, iPad ? 20 : 16)

                        Spacer()

                        Button(action: { window = .None }) {
                            Image(systemName: "xmark.circle.fill")
                                .appThemeFont(.primary, size: iPad ? 30 : 22)
                                .foregroundStyle(PrimaryColor)
                        }
                        .padding(iPad ? 16 : 12)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(PrimaryColor)
                    .glassEffect()
                } else {
                    HStack {
                        Text("What-If Calculator")
                            .appThemeFont(.secondary, size: 24, weight: .bold)
                            .foregroundStyle(PrimaryColor)

                        Spacer()

                        Button(action: { window = .None }) {
                            Image(systemName: "xmark.circle.fill")
                                .appThemeFont(.primary, size: 24)
                                .foregroundStyle(PrimaryColor)
                        }
                    }
                    .padding(20)
                    .background(SecondaryColor)
                    .cornerRadius(16)
                }

                Spacer()
            }
        }
        .onAppear {
            if let first = classOptions.first {
                selectedClassIndex = first.index
            }
        }
    }

    private var currentClassName: String {
        classOptions.first(where: { $0.index == selectedClassIndex })?.name ?? "Selected Class"
    }

    private func percentageField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .appThemeFont(.secondary, size: iPad ? 18 : 14, weight: .semibold)
                .padding(12)
                .foregroundStyle(PrimaryColor)
                .background(SecondaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("%")
                .appThemeFont(.secondary, size: 14, weight: .semibold)
                .foregroundStyle(PrimaryColor)
                .padding(.trailing, 8)
        }
    }

    private func pointField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appThemeFont(.secondary, size: 12, weight: .semibold)
                .foregroundStyle(PrimaryColor.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .appThemeFont(.secondary, size: iPad ? 18 : 14, weight: .semibold)
                .padding(12)
                .foregroundStyle(PrimaryColor)
                .background(SecondaryColor.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func infoCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appThemeFont(.secondary, size: 14, weight: .semibold)
                        .foregroundStyle(PrimaryColor)
                    Text(subtitle)
                        .appThemeFont(.secondary, size: 11, weight: .medium)
                        .foregroundStyle(PrimaryColor.opacity(0.7))
                }
                Spacer()
            }

            content()
        }
        .padding(12)
        .background(SecondaryColor)
        .cornerRadius(12)
    }

    private func deltaText(_ delta: Double) -> String {
        if abs(delta) < 0.01 { return "No meaningful change" }
        return delta > 0
            ? String(format: "Up %.2f points", delta)
            : String(format: "Down %.2f points", abs(delta))
    }

    private var resultDescription: String {
        switch mode {
        case .weightedCategory:
            return "This estimate uses your current overall grade, current category grade, category weight, and the assignment's weight inside that category."
        case .pointsBased:
            return "This estimate uses your current points, total points so far, and the size of the new assignment."
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
