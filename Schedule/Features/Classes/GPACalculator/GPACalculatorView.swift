//
//  GPACalculatorView.swift
//  Schedule
//
//  Created by Andreas Royset on 1/13/26.
//

import SwiftUI

struct GPACalculatorModal: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var window: classWindow
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
        VStack(spacing: 0) {
            HStack {
                Text("GPA Calculator")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(PrimaryColor)
                
                Spacer()
                
                Button(action: { window = .None }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(PrimaryColor)
                }
            }
            .padding(20)
            .background(SecondaryColor)
            .cornerRadius(16)
            
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
                    
                    Text("For your privacy we do not save your grades and therefor will reset opon closing the gpa calculator.")
                        .font(.footnote)
                        .foregroundStyle(TertiaryColor.highContrastTextColor())
                    
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
