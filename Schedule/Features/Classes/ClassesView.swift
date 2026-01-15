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
    case ClassEditor = 3
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
                    Text("Classes")
                        .font(.system(size: iPad ? 34 : 22, weight: .bold, design: .monospaced))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                    
                    Divider()
                    
                    Button(action: { window = .GPACalculator }) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            Text("GPA Calculator")
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(TertiaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .newBadge()
                    
                    Button(action: { window = .CoursesList }) {
                        HStack {
                            Image(systemName: "book.fill")
                            Text("Browse Courses")
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(TertiaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .newBadge()
                    
                    Button(action: { window = .ClassEditor }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit Classes")
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(TertiaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
}
