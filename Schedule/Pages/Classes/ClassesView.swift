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
    
    @State var window = classWindow.None
    @State var gpaGrades: [String] = Array(repeating: "A", count: 7)
    @State var gpaTypes: [String] = Array(repeating: "Normal", count: 7)
    
    @StateObject private var courseViewModel = CourseViewModel()
    
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
                                AppFeatureBadge.whatIfCalculator.markSeen()
                                window = .WhatIfCalculator
                            }
                            .newBadge(AppFeatureBadge.whatIfCalculator.isVisible)
                        }
                    }
                    
                case .GPACalculator:
                    GPACalculatorModal(
                        data: $data,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        window: $window,
                        gpaGrades: $gpaGrades,
                        gpaTypes: $gpaTypes
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
                        window: $window
                    )

                case .WhatIfCalculator:
                    WhatIfGradeCalculatorModal(
                        data: $data,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                        window: $window
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
            gpaTypes = data.classes.prefix(7).map { inferClassLevel(from: $0.name) }
        })
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
}
