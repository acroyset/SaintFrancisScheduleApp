//
//  ClassesView.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation
import SwiftUI

enum classWindow: Int{
    case None = 0
    case GPACalculator = 1
    case CoursesList = 2
    case FinalGradeCalculator = 3
    case ClassEditor = 4
    case WhatIfCalculator = 5
}

func inferClassLevel(from className: String) -> String {
    let lowerName = className.lowercased()
    
    if lowerName.contains("ap") {
        return "AP"
    } else if lowerName.contains("honors") || lowerName.contains("honors") {
        return "Honors"
    } else {
        return "Normal"
    }
}

struct ClassesView: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var isPortrait: Bool
    var openClassEditor: Binding<Bool> = .constant(false)
    
    @State var window = classWindow.None
    @StateObject private var courseViewModel = CourseViewModel()
    @StateObject private var localGradeStore = LocalGradeStore.shared
    
    var body: some View {
        ZStack{
            VStack{
                
                switch window {
                    
                case .None:
                    VStack(spacing: 16) {
                        Text("Classes")
                            .appThemeFont(.secondary, size: iPad ? 34 : 22, weight: .bold)
                            .padding(.top, 12)
                            .foregroundStyle(PrimaryColor)

                        sectionCard(title: "Class Management") {
                            menuButton(title: "Edit Classes", systemImage: "pencil") {
                                window = .ClassEditor
                            }
                            menuDivider
                            menuButton(title: "Browse Courses", systemImage: "book.fill") {
                                window = .CoursesList
                            }
                        }

                        sectionCard(title: "Grade Tools") {
                            menuButton(title: "GPA Calculator", systemImage: "chart.bar.fill") {
                                window = .GPACalculator
                            }
                            menuDivider
                            menuButton(title: "Final Grade Calculator", systemImage: "percent") {
                                window = .FinalGradeCalculator
                            }
                            menuDivider
                            menuButton(title: "What-If Calculator", systemImage: "wand.and.stars") {
                                window = .WhatIfCalculator
                            }
                        }
                    }
                    
                case .GPACalculator:
                    GPACalculatorModal(
                        data: $data,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        window: $window,
                        localGradeStore: localGradeStore
                    )
                    
                case .CoursesList:
                    CourseSchedulingView(
                        courseViewModel: courseViewModel,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        window: $window
                    )
                    
                case .FinalGradeCalculator:
                    FinalGradeCalculatorModal(
                        data: $data,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        window: $window,
                        localGradeStore: localGradeStore
                    )

                case .WhatIfCalculator:
                    WhatIfGradeCalculatorModal(
                        data: $data,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        window: $window,
                        localGradeStore: localGradeStore
                    )
                    
                case .ClassEditor:
                    if (iPad || isPortrait){
                        VphoneClassEditor(
                            data: $data,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            isPortrait: isPortrait,
                            window: $window
                        )
                    } else {
                        HphoneClassEditor(
                            data: $data,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            window: $window
                        )
                    }
                }
                
                Spacer()
            }
        }
        .onAppear(perform: {
            courseViewModel.allCourses = loadSFHSCourses()
            localGradeStore.seedClassTypes(from: data)
            openRequestedClassEditor()
            UsageStatsStore.shared.setCurrentFeature(feature(for: window))
        })
        .onChange(of: openClassEditor.wrappedValue) { _, _ in
            openRequestedClassEditor()
        }
        .onChange(of: window) { _, newWindow in
            UsageStatsStore.shared.setCurrentFeature(feature(for: newWindow))
        }
        .onChange(of: data.classes.map(\.name)) { _, _ in
            localGradeStore.seedClassTypes(from: data)
        }
    }

    private func openRequestedClassEditor() {
        guard openClassEditor.wrappedValue else { return }

        window = .ClassEditor
        openClassEditor.wrappedValue = false
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .appThemeFont(.secondary, size: 12, weight: .bold)
                .foregroundStyle(PrimaryColor.opacity(0.65))

            VStack(spacing: 0) {
                content()
            }
            .background(SecondaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func menuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .appThemeFont(.primary, size: 16, weight: .semibold)
                    .frame(width: 22)
                Text(title)
                    .appThemeFont(.secondary, size: 15, weight: .bold)
                Spacer()
                Image(systemName: "chevron.right")
                    .appThemeFont(.primary, size: 13, weight: .semibold)
                    .foregroundStyle(PrimaryColor.opacity(0.7))
            }
            .foregroundStyle(PrimaryColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    private var menuDivider: some View {
        Divider().padding(.leading, 48)
    }

    private func feature(for window: classWindow) -> UsageFeature? {
        switch window {
        case .GPACalculator:
            .gpaCalculator
        case .CoursesList:
            .courseBrowser
        case .FinalGradeCalculator:
            .finalGradeCalculator
        case .ClassEditor:
            .classEditor
        case .WhatIfCalculator:
            .whatIfCalculator
        case .None:
            nil
        }
    }
}

#if DEBUG
private struct ClassesViewPreviewWrapper: View {
    @State private var data = ScheduleData(
        classes: [
            ClassItem(name: "AP Biology", teacher: "Dr. Patel", room: "S201"),
            ClassItem(name: "English 2 Honors", teacher: "Ms. Lopez", room: "B104"),
            ClassItem(name: "Algebra 2", teacher: "Mr. Chen", room: "M301"),
            ClassItem(name: "US History", teacher: "Mr. Grant", room: "H210"),
            ClassItem(name: "Spanish 3", teacher: "Sra. Ruiz", room: "L112"),
            ClassItem(name: "Chemistry", teacher: "Dr. Kim", room: "S115"),
            ClassItem(name: "Design Lab", teacher: "Ms. Hart", room: "A008")
        ] + Array(ScheduleData.defaultClasses.dropFirst(7)),
        days: [],
        isSecondLunch: [false, false]
    ).normalized()

    var body: some View {
        ClassesView(
            data: $data,
            PrimaryColor: .blue,
            SecondaryColor: Color.blue.opacity(0.12),
            TertiaryColor: .white,
            isPortrait: true
        )
    }
}

#Preview("Classes Page") {
    ClassesViewPreviewWrapper()
}
#endif
