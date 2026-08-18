//
//  ClassDetailView.swift
//  Schedule
//

import SwiftUI

struct ClassDetailView: View {
    private enum GradeTool: String, Identifiable {
        case gpa
        case whatIf
        case finalGrade

        var id: String { rawValue }

        var window: classWindow {
            switch self {
            case .gpa: return .GPACalculator
            case .whatIf: return .WhatIfCalculator
            case .finalGrade: return .FinalGradeCalculator
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var homeworkStore: HomeworkStore
    @ObservedObject private var localGradeStore = LocalGradeStore.shared

    let classItem: ClassItem
    let classIndex: Int
    let timeRange: String
    let classes: [ClassItem]
    let currentDate: Date
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    @State private var showingAddHomework = false
    @State private var editingHomework: HomeworkItem?
    @State private var presentedGradeTool: GradeTool?

    private var homeworkItems: [HomeworkItem] {
        homeworkStore.items(forClass: classItem)
    }

    private var openHomework: [HomeworkItem] {
        homeworkItems.filter { !$0.isComplete }
    }

    private var completedHomework: [HomeworkItem] {
        homeworkItems.filter(\.isComplete)
    }

    private var gradeRecord: LocalClassGradeRecord {
        localGradeStore.record(for: classIndex, className: classItem.name)
    }

    private var gradePercentage: Double? {
        guard let value = Double(gradeRecord.gpaPercentage), (0...100).contains(value) else {
            return nil
        }
        return value
    }

    private var calculatorData: Binding<ScheduleData> {
        Binding(
            get: { ScheduleData(classes: classes, days: []) },
            set: { _ in }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    classHeader
                    gradeCard
                    homeworkCard
                    gradeToolsCard

                    Text("Grade information is stored locally on this device.")
                        .appThemeFont(.secondary, size: 11, weight: .medium)
                        .foregroundStyle(PrimaryColor.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(TertiaryColor.ignoresSafeArea())
            .navigationTitle("Class Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PrimaryColor)
                }
            }
        }
        .tint(PrimaryColor)
        .sheet(isPresented: $showingAddHomework) {
            AddHomeworkView(
                isPresented: $showingAddHomework,
                editingHomework: nil,
                homeworkStore: homeworkStore,
                classes: classes,
                currentDate: currentDate,
                initialClassName: classItem.name,
                initialClassID: classItem.id,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(item: $editingHomework) { item in
            AddHomeworkView(
                isPresented: Binding(
                    get: { editingHomework != nil },
                    set: { if !$0 { editingHomework = nil } }
                ),
                editingHomework: item,
                homeworkStore: homeworkStore,
                classes: classes,
                currentDate: currentDate,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .fullScreenCover(item: $presentedGradeTool) { tool in
            gradeToolView(tool)
        }
    }

    private var classHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(classItem.name.isEmpty ? "Class" : classItem.name)
                    .appThemeFont(.primary, size: iPad ? 30 : 24, weight: .bold)
                    .foregroundStyle(TertiaryColor)

                Spacer(minLength: 12)

                if let gradePercentage {
                    Text("\(gradeLetter(for: gradePercentage))  \(gradePercentage.formatted(.number.precision(.fractionLength(0...1))))%")
                        .appThemeFont(.secondary, size: 13, weight: .bold)
                        .foregroundStyle(PrimaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TertiaryColor)
                        .clipShape(Capsule())
                }
            }

            if !timeRange.isEmpty {
                Label(timeRange, systemImage: "clock.fill")
            }

            if !classItem.teacher.isEmpty {
                Label(classItem.teacher, systemImage: "person.fill")
            }

            if !classItem.room.isEmpty {
                Label(classItem.room, systemImage: "mappin.and.ellipse")
            }
        }
        .appThemeFont(.secondary, size: 14, weight: .semibold)
        .foregroundStyle(TertiaryColor.opacity(0.88))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PrimaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var gradeCard: some View {
        detailCard(title: "Grade", systemImage: "chart.bar.fill") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CURRENT GRADE")
                        .appThemeFont(.secondary, size: 10, weight: .bold)
                        .foregroundStyle(PrimaryColor.opacity(0.62))

                    HStack(spacing: 6) {
                        TextField(
                            "--",
                            text: localGradeStore.binding(
                                for: classIndex,
                                className: classItem.name,
                                keyPath: \.gpaPercentage
                            )
                        )
                        .keyboardType(.decimalPad)
                        .appThemeFont(.primary, size: 22, weight: .bold)
                        .foregroundStyle(PrimaryColor)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)

                        Text("%")
                            .appThemeFont(.secondary, size: 15, weight: .bold)
                            .foregroundStyle(PrimaryColor.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(TertiaryColor.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("CLASS TYPE")
                        .appThemeFont(.secondary, size: 10, weight: .bold)
                        .foregroundStyle(PrimaryColor.opacity(0.62))

                    Picker(
                        "Class Type",
                        selection: localGradeStore.binding(
                            for: classIndex,
                            className: classItem.name,
                            keyPath: \.gpaType
                        )
                    ) {
                        ForEach(["Normal", "Honors", "AP"], id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(TertiaryColor.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let gradePercentage {
                    VStack(spacing: 5) {
                        Text("LETTER")
                            .appThemeFont(.secondary, size: 10, weight: .bold)
                            .foregroundStyle(PrimaryColor.opacity(0.62))

                        Text(gradeLetter(for: gradePercentage))
                            .appThemeFont(.primary, size: 20, weight: .bold)
                            .foregroundStyle(TertiaryColor)
                            .frame(width: 52, height: 44)
                            .background(PrimaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var homeworkCard: some View {
        detailCard(title: "Homework", systemImage: "checklist") {
            VStack(spacing: 10) {
                if homeworkItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .appThemeFont(.primary, size: 26, weight: .semibold)
                        Text("No homework for this class")
                            .appThemeFont(.secondary, size: 13, weight: .semibold)
                    }
                    .foregroundStyle(PrimaryColor.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    homeworkSection(title: "Open", items: openHomework)
                    homeworkSection(title: "Completed", items: Array(completedHomework.prefix(5)))
                }

                Button {
                    showingAddHomework = true
                } label: {
                    Label("Add Homework", systemImage: "plus")
                        .appThemeFont(.secondary, size: 14, weight: .bold)
                        .foregroundStyle(TertiaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gradeToolsCard: some View {
        detailCard(title: "Grade Tools", systemImage: "function") {
            VStack(spacing: 0) {
                gradeToolButton(
                    title: "GPA Calculator",
                    subtitle: "See weighted and unweighted GPA",
                    systemImage: "chart.bar.fill",
                    tool: .gpa
                )
                Rectangle()
                    .fill(PrimaryColor.opacity(0.18))
                    .frame(height: 1)
                    .padding(.leading, 44)
                gradeToolButton(
                    title: "What-If Calculator",
                    subtitle: "Preview the impact of an assignment",
                    systemImage: "wand.and.stars",
                    tool: .whatIf
                )
                Rectangle()
                    .fill(PrimaryColor.opacity(0.18))
                    .frame(height: 1)
                    .padding(.leading, 44)
                gradeToolButton(
                    title: "Final Grade Calculator",
                    subtitle: "Calculate the score needed on your final",
                    systemImage: "percent",
                    tool: .finalGrade
                )
            }
        }
    }

    @ViewBuilder
    private func homeworkSection(title: String, items: [HomeworkItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title.uppercased())
                    .appThemeFont(.secondary, size: 10, weight: .bold)
                    .foregroundStyle(PrimaryColor.opacity(0.58))

                ForEach(items) { item in
                    HomeworkRow(
                        item: item,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        iPad: iPad,
                        onToggle: { homeworkStore.toggleComplete(item) },
                        onEdit: { editingHomework = item },
                        onDelete: { homeworkStore.delete(item) }
                    )
                }
            }
        }
    }

    private func gradeToolButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tool: GradeTool
    ) -> some View {
        Button {
            presentedGradeTool = tool
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .appThemeFont(.primary, size: 16, weight: .semibold)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appThemeFont(.secondary, size: 14, weight: .bold)
                    Text(subtitle)
                        .appThemeFont(.secondary, size: 11, weight: .medium)
                        .foregroundStyle(PrimaryColor.opacity(0.62))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appThemeFont(.primary, size: 12, weight: .bold)
                    .foregroundStyle(PrimaryColor.opacity(0.5))
            }
            .foregroundStyle(PrimaryColor)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .appThemeFont(.secondary, size: 16, weight: .bold)
                .foregroundStyle(PrimaryColor)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SecondaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func gradeToolView(_ tool: GradeTool) -> some View {
        switch tool {
        case .gpa:
            GPACalculatorModal(
                data: calculatorData,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                window: gradeToolWindowBinding(for: tool),
                localGradeStore: localGradeStore
            )
        case .whatIf:
            WhatIfGradeCalculatorModal(
                data: calculatorData,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                window: gradeToolWindowBinding(for: tool),
                localGradeStore: localGradeStore,
                initialClassIndex: classIndex
            )
        case .finalGrade:
            FinalGradeCalculatorModal(
                data: calculatorData,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                window: gradeToolWindowBinding(for: tool),
                localGradeStore: localGradeStore,
                initialClassIndex: classIndex
            )
        }
    }

    private func gradeToolWindowBinding(for tool: GradeTool) -> Binding<classWindow> {
        Binding(
            get: { tool.window },
            set: { newValue in
                if newValue == .None {
                    presentedGradeTool = nil
                }
            }
        )
    }

    private func gradeLetter(for percentage: Double) -> String {
        switch percentage {
        case 92.5...100: return "A"
        case 89.5..<92.5: return "A-"
        case 86.5..<89.5: return "B+"
        case 82.5..<86.5: return "B"
        case 79.5..<82.5: return "B-"
        case 76.5..<79.5: return "C+"
        case 72.5..<76.5: return "C"
        case 69.5..<72.5: return "C-"
        case 66.5..<69.5: return "D+"
        case 62.5..<66.5: return "D"
        case 59.5..<62.5: return "D-"
        default: return "F"
        }
    }
}
