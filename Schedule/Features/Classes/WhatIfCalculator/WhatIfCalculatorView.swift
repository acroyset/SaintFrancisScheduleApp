//
//  WhatIfCalculatorView.swift
//  Schedule
//

import SwiftUI

struct WhatIfGradeCalculatorModal: View {
    private enum CategoryScenario: String, CaseIterable, Identifiable {
        case singleAssignment = "Single Assignment Category"
        case multiAssignment = "Shared Category"

        var id: String { rawValue }
    }

    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var window: classWindow
    @ObservedObject var localGradeStore: LocalGradeStore

    @State private var categoryScenario: CategoryScenario = .singleAssignment
    @State private var selectedClassIndex: Int = 0

    private var classOptions: [(index: Int, name: String)] {
        data.classes.enumerated().compactMap { index, item in
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard index < 7, !trimmed.isEmpty, trimmed != "None", trimmed != "Period \(index + 1)" else { return nil }
            return (index, trimmed)
        }
    }

    private var selectedClassName: String {
        classOptions.first(where: { $0.index == selectedClassIndex })?.name ?? ""
    }

    private var currentGradeBinding: Binding<String> {
        localGradeStore.binding(for: selectedClassIndex, className: selectedClassName, keyPath: \.gpaPercentage)
    }

    private var categoryScenarioBinding: Binding<String> {
        localGradeStore.binding(for: selectedClassIndex, className: selectedClassName, keyPath: \.categoryScenario)
    }

    private var categoryGradeBinding: Binding<String> {
        localGradeStore.binding(for: selectedClassIndex, className: selectedClassName, keyPath: \.categoryGrade)
    }

    private var categoryWeightBinding: Binding<String> {
        localGradeStore.binding(for: selectedClassIndex, className: selectedClassName, keyPath: \.categoryWeight)
    }

    private var assignmentWeightBinding: Binding<String> {
        localGradeStore.binding(for: selectedClassIndex, className: selectedClassName, keyPath: \.assignmentWeightInCategory)
    }

    private var hypotheticalScoreBinding: Binding<String> {
        localGradeStore.binding(for: selectedClassIndex, className: selectedClassName, keyPath: \.hypotheticalScore)
    }

    private var selectedRecord: LocalClassGradeRecord {
        localGradeStore.record(for: selectedClassIndex, className: selectedClassName)
    }

    private var result: (newGrade: Double, delta: Double)? {
        let assignmentWeightValue = categoryScenario == .singleAssignment ? 100 : Double(selectedRecord.assignmentWeightInCategory)
        let categoryCurrentValue = categoryScenario == .singleAssignment ? selectedRecord.gpaPercentage : selectedRecord.categoryGrade

        guard let current = Double(selectedRecord.gpaPercentage),
              let categoryCurrent = Double(categoryCurrentValue),
              let categoryWeightValue = Double(selectedRecord.categoryWeight),
              let assignmentWeightValue,
              let score = Double(selectedRecord.hypotheticalScore),
              (0...100).contains(current),
              (0...100).contains(categoryCurrent),
              (0...100).contains(categoryWeightValue),
              (0...100).contains(assignmentWeightValue),
              (0...100).contains(score),
              categoryWeightValue > 0,
              assignmentWeightValue > 0,
              assignmentWeightValue <= 100 else {
            return nil
        }

        let updatedCategoryGrade =
            categoryCurrent * (1 - assignmentWeightValue / 100) +
            score * (assignmentWeightValue / 100)

        let newGrade =
            current +
            (updatedCategoryGrade - categoryCurrent) * (categoryWeightValue / 100)

        return (newGrade, newGrade - current)
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
                        subtitle: "This is shared with the percentage saved in GPA Calculator."
                    ) {
                        percentageField(text: currentGradeBinding, placeholder: "90")
                    }

                    infoCard(
                        title: "Category Setup",
                        subtitle: "Pick the option that matches how this assignment fits into the gradebook."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            categoryScenarioSelector

                            Text(categoryScenarioDescription)
                                .appThemeFont(.secondary, size: 11, weight: .medium)
                                .foregroundStyle(PrimaryColor.opacity(0.72))
                        }
                    }

                    if categoryScenario == .multiAssignment {
                        infoCard(
                            title: "Category Grade",
                            subtitle: "Your current grade inside that category."
                        ) {
                            percentageField(text: categoryGradeBinding, placeholder: "88")
                        }
                    }

                    infoCard(
                        title: "Category Weight",
                        subtitle: "How much that category counts toward your class grade."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            percentageField(text: categoryWeightBinding, placeholder: "30")

                            presetChips(
                                values: ["10", "15", "20", "25", "30", "40", "50"],
                                selection: categoryWeightBinding
                            )
                        }
                    }

                    if categoryScenario == .multiAssignment {
                        infoCard(
                            title: "Assignment Share Of Category",
                            subtitle: "Only use this if the category has multiple assignments."
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                percentageField(text: assignmentWeightBinding, placeholder: "20")

                                presetChips(
                                    values: ["5", "10", "15", "20", "25", "50"],
                                    selection: assignmentWeightBinding
                                )
                            }
                        }
                    } else {
                        infoCard(
                            title: "Assignment Share Of Category",
                            subtitle: "This assignment is the whole category, so we count it as 100% automatically."
                        ) {
                            Text("We use your score as the category grade automatically.")
                                .appThemeFont(.secondary, size: 12, weight: .semibold)
                                .foregroundStyle(PrimaryColor.opacity(0.78))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                    }

                    infoCard(
                        title: "What If I Get...",
                        subtitle: "The score you want to test on that assignment."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            percentageField(text: hypotheticalScoreBinding, placeholder: "100")

                            presetChips(
                                values: ["100", "95", "90", "85", "80", "75", "70"],
                                selection: hypotheticalScoreBinding
                            )
                        }
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

                    Text("Your grade data is stored locally on this device. It is not sent to us, and we do not collect it.")
                        .appThemeFont(.secondary, style: .footnote)
                        .foregroundStyle(TertiaryColor.highContrastTextColor())
                }
                .padding(16)

                Color.clear.frame(height: iPad ? 60 : 50)
            }
            .onTapGesture { hideKeyboard() }
            .scrollDismissesKeyboard(.interactively)
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
            syncCategoryScenarioFromStore()
        }
        .onChange(of: selectedClassIndex) { _, _ in
            syncCategoryScenarioFromStore()
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

    private func presetChips(values: [String], selection: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button(action: { selection.wrappedValue = value }) {
                        Text("\(value)%")
                            .appThemeFont(.secondary, size: 11, weight: .semibold)
                            .foregroundStyle(selection.wrappedValue == value ? TertiaryColor : PrimaryColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selection.wrappedValue == value ? PrimaryColor : SecondaryColor.opacity(0.9))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var categoryScenarioSelector: some View {
        HStack(spacing: 8) {
            ForEach(CategoryScenario.allCases) { scenario in
                Button {
                    categoryScenario = scenario
                    categoryScenarioBinding.wrappedValue = scenario.rawValue
                } label: {
                    Text(scenario.rawValue)
                        .appThemeFont(.secondary, size: 11, weight: .bold)
                        .foregroundStyle(categoryScenario == scenario ? TertiaryColor : PrimaryColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(categoryScenario == scenario ? PrimaryColor : SecondaryColor.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
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

    private var categoryScenarioDescription: String {
        switch categoryScenario {
        case .singleAssignment:
            return "Best for categories that only have one assignment. You do not need to enter a category grade or assignment weight."
        case .multiAssignment:
            return "Use this when the category already has multiple assignments and this new score is only part of it."
        }
    }

    private func syncCategoryScenarioFromStore() {
        categoryScenario = CategoryScenario(rawValue: selectedRecord.categoryScenario) ?? .singleAssignment
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
