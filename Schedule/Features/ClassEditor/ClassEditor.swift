//
//  ClassEditor.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation
import SwiftUI

struct ClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var isPortrait: Bool
    
    @State var selector = 0
    @State var showGPAModal = false
    @State var gpaGrades: [String] = Array(repeating: "A", count: 7)
    @State var gpaTypes: [String] = Array(repeating: "Normal", count: 7)
    
    var body: some View {
        ZStack{
            if (iPad || isPortrait){
                VphoneClassEditor(
                    data: $data,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor,
                    isPortrait: isPortrait,
                    showGPAModal: $showGPAModal,
                    gpaGrades: $gpaGrades,
                    gpaTypes: $gpaTypes
                )
            } else {
                HphoneClassEditor(
                    data: $data,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor,
                    showGPAModal: $showGPAModal,
                    gpaGrades: $gpaGrades,
                    gpaTypes: $gpaTypes
                )
            }
            
            // GPA Calculator Modal
            if showGPAModal {
                GPACalculatorModal(
                    data: $data,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor,
                    showModal: $showGPAModal,
                    gpaGrades: $gpaGrades,
                    gpaTypes: $gpaTypes
                )
            }
        }
    }
}

// MARK: - GPA Calculator Modal
struct GPACalculatorModal: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var showModal: Bool
    @Binding var gpaGrades: [String]
    @Binding var gpaTypes: [String]
    
    let grades = ["A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"]
    let classTypes = ["Normal", "Honors", "AP"]
    
    func gradeToGPA(_ grade: String, isHonors: Bool, isAP: Bool) -> Double {
        let baseGPA: [String: Double] = [
            "A": 4.0,  "A-": 3.7,
            "B+": 3.3, "B": 3.0, "B-": 2.7,
            "C+": 2.3, "C": 2.0, "C-": 1.7,
            "D+": 1.3, "D": 1.0, "D-": 0.7,
            "F": 0.0
        ]
        
        var gpa = baseGPA[grade] ?? 0.0
        if grade != "" {
            if isHonors { gpa += 1.0 }
            if isAP { gpa += 1.0 }
        }
        return min(gpa, 5.0)
    }
    
    func calculateGPA(isWeighted: Bool) -> Double {
        let validGrades = gpaGrades.filter { $0 != "" }
        
        if validGrades.isEmpty { return 0.0 }
        
        let totalGPA = (0..<7).reduce(0.0) { sum, index in
            let isHonors = gpaTypes[index] == "Honors" && isWeighted
            let isAP = gpaTypes[index] == "AP" && isWeighted
            return sum + gradeToGPA(gpaGrades[index], isHonors: isHonors, isAP: isAP)
        }
        
        return totalGPA / Double(validGrades.count)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text("GPA Calculator")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(PrimaryColor)
                    
                    Spacer()
                    
                    Button(action: { showModal = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(PrimaryColor)
                    }
                }
                .padding(20)
                .background(SecondaryColor)
                
                ScrollView {
                    VStack(spacing: 12) {
                        // GPA Display
                        HStack{
                            VStack(spacing: 8) {
                                Text("Weighted")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PrimaryColor)
                                
                                Text(String(format: "%.2f", calculateGPA(isWeighted: true)))
                                    .font(.system(size: 48, weight: .bold, design: .default))
                                    .foregroundStyle(PrimaryColor)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            
                            VStack(spacing: 8) {
                                Text("Unweighted")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PrimaryColor)
                                
                                Text(String(format: "%.2f", calculateGPA(isWeighted: false)))
                                    .font(.system(size: 48, weight: .bold, design: .default))
                                    .foregroundStyle(PrimaryColor)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Classes with grade selection
                        VStack(spacing: 12) {
                            ForEach(0..<7, id: \.self) { index in
                                VStack(spacing: 8) {
                                    Text(data.classes[index].name.isEmpty ? "Class Name" : data.classes[index].name)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(PrimaryColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Grade")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(PrimaryColor.opacity(0.7))
                                            
                                            Picker("Grade", selection: $gpaGrades[index]) {
                                                ForEach(grades, id: \.self) { grade in
                                                    Text(grade).tag(grade)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .tint(PrimaryColor)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Type")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(PrimaryColor.opacity(0.7))
                                            
                                            Picker("Type", selection: $gpaTypes[index]) {
                                                ForEach(classTypes, id: \.self) { type in
                                                    Text(type).tag(type)
                                                }
                                            }
                                            .tint(PrimaryColor)
                                            .frame(maxWidth: .infinity)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("GPA")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(PrimaryColor.opacity(0.7))
                                            
                                            Text(String(format: "%.2f", gradeToGPA(gpaGrades[index], isHonors: gpaTypes[index] == "Honors", isAP: gpaTypes[index] == "AP")))
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundStyle(PrimaryColor)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(SecondaryColor)
                                .cornerRadius(16)
                                .shadow(radius: 20)
                            }
                        }
                    }
                    .padding(16)
                }
                
                Button(action: { showModal = false }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
            .frame(maxWidth: 500)
            .background(TertiaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(16)
            .shadow(radius: 20)
        }
    }
}

struct OutlinedTextFieldStyle: TextFieldStyle {
    var lineWidth: CGFloat = 1
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(TertiaryColor)
    }
}

// MARK: - VphoneClassEditor
struct VphoneClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var isPortrait: Bool
    @Binding var showGPAModal: Bool
    @Binding var gpaGrades: [String]
    @Binding var gpaTypes: [String]
    
    var body: some View {
        VStack{
            Text("Classes")
                .font(.system(size: iPad ? 34 : 22, weight: .bold, design: .monospaced))
                .padding(12)
                .foregroundStyle(PrimaryColor)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    
                    // GPA Calculator Button
                    Button(action: { showGPAModal = true }) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            Text("GPA Calculator")
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(PrimaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(12)
                    
                    
                    // Second Lunch Toggle
                    HStack(spacing: 40) {
                        Text("Second Lunch")
                            .font(.system(size: iPad ? 20 : 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrimaryColor)
                        
                        VStack {
                            HStack(spacing: 8) {
                                Text("Gold Day")
                                    .font(.system(size: iPad ? 18 : 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PrimaryColor)
                                
                                Toggle("", isOn: $data.isSecondLunch[0])
                                    .toggleStyle(SwitchToggleStyle(tint: PrimaryColor))
                            }
                            .fixedSize()
                            
                            HStack(spacing: 8) {
                                Text("Brown Day")
                                    .font(.system(size: iPad ? 18 : 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PrimaryColor)
                                
                                Toggle("", isOn: $data.isSecondLunch[1])
                                    .toggleStyle(SwitchToggleStyle(tint: PrimaryColor))
                            }
                            .fixedSize()
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(SecondaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    let indices: [Int] = [0, 1, 2, 3, 4, 5, 6, 9, 12]
                    
                    ForEach(indices, id: \.self) { (number: Int) in
                        HStack{
                            if number <= 6{
                                TextFieldClassEditor(
                                    inputText: $data.classes[number].name,
                                    defaultText: "Period \(number + 1)",
                                    PrimaryColor: PrimaryColor,
                                    SecondaryColor: SecondaryColor,
                                    TertiaryColor: TertiaryColor
                                )
                            } else {
                                Text(data.classes[number].name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .font(.system(
                                        size: iPad ? 20 : 14,
                                        weight: .bold,
                                        design: .monospaced
                                    ))
                                    .padding(12)
                                    .foregroundStyle(PrimaryColor)
                                    .background(SecondaryColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            
                            TextFieldClassEditor(
                                inputText: $data.classes[number].teacher,
                                defaultText: "Teacher",
                                PrimaryColor: PrimaryColor,
                                SecondaryColor: SecondaryColor,
                                TertiaryColor: TertiaryColor,
                            )
                            
                            TextFieldClassEditor(
                                inputText: $data.classes[number].room,
                                defaultText: "Room #",
                                PrimaryColor: PrimaryColor,
                                SecondaryColor: SecondaryColor,
                                TertiaryColor: TertiaryColor
                            )
                            .frame(maxWidth: iPad ? .infinity : 60)
                        }
                    }
                    
                    Spacer(minLength: 200)
                }
                .padding(12)
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - HphoneClassEditor
struct HphoneClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var showGPAModal: Bool
    @Binding var gpaGrades: [String]
    @Binding var gpaTypes: [String]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Classes")
                    .font(.system(
                        size: iPad ? 34 : 22,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(PrimaryColor)
                
                Divider()
                
                // GPA Calculator Button
                Button(action: { showGPAModal = true }) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("GPA Calculator")
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(PrimaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
                
                Divider()
                
                // Second Lunch Toggle
                HStack(spacing: 40) {
                    Text("Second Lunch")
                        .font(.system(
                            size: iPad ? 20 : 16,
                            weight: .semibold,
                            design: .monospaced
                        ))
                        .foregroundStyle(PrimaryColor)
                    
                    VStack{
                        
                        HStack(spacing: 8) {
                            
                            Text("Gold Day")
                                .font(.system(
                                    size: iPad ? 18 : 14,
                                    weight: .semibold,
                                    design: .monospaced
                                ))
                                .foregroundStyle(PrimaryColor)
                            
                            Toggle("", isOn: $data.isSecondLunch[0])
                                .toggleStyle(SwitchToggleStyle(tint: PrimaryColor))
                        }
                        .fixedSize()
                        
                        HStack(spacing: 8) {
                            
                            Text("Brown Day")
                                .font(.system(
                                    size: iPad ? 18 : 14,
                                    weight: .semibold,
                                    design: .monospaced
                                ))
                                .foregroundStyle(PrimaryColor)
                            
                            Toggle("", isOn: $data.isSecondLunch[1])
                                .toggleStyle(SwitchToggleStyle(tint: PrimaryColor))
                        }
                        .fixedSize()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(SecondaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                
                HStack{
                    let indices: [Int] = [0, 1, 2, 3, 4, 5, 6, 9, 12]
                    
                    ForEach(indices, id: \.self) { (number: Int) in
                        VStack{
                            if number <= 6{
                                TextFieldClassEditor(
                                    inputText: $data.classes[number].name,
                                    defaultText: "Period \(number + 1)",
                                    PrimaryColor: PrimaryColor,
                                    SecondaryColor: SecondaryColor,
                                    TertiaryColor: TertiaryColor
                                )
                            } else {
                                Text(data.classes[number].name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .font(.system(
                                        size: iPad ? 20 : 14,
                                        weight: .bold,
                                        design: .monospaced
                                    ))
                                    .padding(12)
                                    .foregroundStyle(PrimaryColor)
                                    .background(SecondaryColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            
                            TextFieldClassEditor(
                                inputText: $data.classes[number].teacher,
                                defaultText: "Teacher",
                                PrimaryColor: PrimaryColor,
                                SecondaryColor: SecondaryColor,
                                TertiaryColor: TertiaryColor,
                            )
                            
                            TextFieldClassEditor(
                                inputText: $data.classes[number].room,
                                defaultText: "Room #",
                                PrimaryColor: PrimaryColor,
                                SecondaryColor: SecondaryColor,
                                TertiaryColor: TertiaryColor
                            )
                            .frame(maxWidth: iPad ? .infinity : 60)
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(12)
        }
    }
}
