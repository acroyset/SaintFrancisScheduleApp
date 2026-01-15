//
//  FinalGradeCalculator.swift
//  Schedule
//
//  Created by Andreas Royset on 1/14/26.
//

import SwiftUI

struct FinalGradeCalculatorModal: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var window: classWindow
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentGrade: String = "90"
    @State private var finalExamWeight: String = "15"
    @State private var desiredGrade: String = "A"
    @State private var requiredFinalGrade: Double? = nil
    
    let grades = ["A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Final Grade Calculator")
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
                    // Current Grade Input
                    VStack(spacing: 8) {
                        Text("Current Grade")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrimaryColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 8) {
                            TextField("Enter percentage", text: $currentGrade)
                                .keyboardType(.decimalPad)
                                .font(.system(size: iPad ? 18 : 14, weight: .semibold, design: .monospaced))
                                .padding(12)
                                .foregroundStyle(PrimaryColor)
                                .background(SecondaryColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            Text("%")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PrimaryColor)
                                .padding(.trailing, 8)
                        }
                    }
                    .padding(12)
                    .background(SecondaryColor)
                    .cornerRadius(12)
                    
                    VStack(spacing: 8) {
                        Text("Weight of Final Exam")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrimaryColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 8) {
                            TextField("Enter weight", text: $finalExamWeight)
                                .keyboardType(.decimalPad)
                                .font(.system(size: iPad ? 18 : 14, weight: .semibold, design: .monospaced))
                                .padding(12)
                                .foregroundStyle(PrimaryColor)
                                .background(SecondaryColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            Text("%")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PrimaryColor)
                                .padding(.trailing, 8)
                        }
                    }
                    .padding(12)
                    .background(SecondaryColor)
                    .cornerRadius(12)
                    
                    // Desired Grade
                    VStack(spacing: 8) {
                        Text("Desired Grade")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrimaryColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Picker("Desired Grade", selection: $desiredGrade) {
                            ForEach(grades, id: \.self) { grade in
                                Text(grade).tag(grade)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(PrimaryColor)
                    }
                    .padding(12)
                    .background(SecondaryColor)
                    .cornerRadius(12)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Required Final Grade Result
                    if let required = calculateRequiredFinalGrade() {
                        VStack(spacing: 12) {
                            HStack {
                                Text("You need on the final exam:")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PrimaryColor)
                                Spacer()
                            }
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(PrimaryColor)
                                
                                VStack(spacing: 4) {
                                    Text(String(format: "%.1f%%", required.percentage))
                                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                                        .foregroundColor(TertiaryColor)
                                    
                                    Text(required.status)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(TertiaryColor.opacity(0.8))
                                }
                                .padding(16)
                            }
                            .frame(minHeight: 80)
                        }
                        .padding(12)
                        .background(SecondaryColor)
                        .cornerRadius(12)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 24))
                                .foregroundStyle(PrimaryColor.opacity(0.5))
                            
                            Text("Enter valid percentages to calculate")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PrimaryColor.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(SecondaryColor)
                        .cornerRadius(12)
                    }
                }
                .padding(16)
            }
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
    
    private func calculateRequiredFinalGrade() -> (percentage: Double, status: String)? {
        // Parse inputs
        guard let currentGradeValue = Double(currentGrade),
              let finalExamWeightValue = Double(finalExamWeight) else {
            return nil
        }
        
        let currentWeightValue = 100-finalExamWeightValue
        
        // Validate inputs
        guard currentGradeValue >= 0 && currentGradeValue <= 100,
              currentWeightValue >= 0 && currentWeightValue <= 100,
              finalExamWeightValue >= 0 && finalExamWeightValue <= 100,
              (currentWeightValue + finalExamWeightValue) <= 100 else {
            return nil
        }
        
        // Get desired grade as percentage
        let desiredGradePercentage = gradeToPercentage(desiredGrade)
        
        // Calculate required final grade
        // Formula: (Desired - (Current × CurrentWeight/100)) / (FinalWeight/100)
        let currentGradeContribution = currentGradeValue * (currentWeightValue / 100)
        let remainingNeeded = desiredGradePercentage - currentGradeContribution
        let requiredOnFinal = remainingNeeded / (finalExamWeightValue / 100)
        
        // Clamp to 0-100 range and determine status
        let clampedRequired = max(0, requiredOnFinal)
        let status: String
        
        if requiredOnFinal < 50 {
            status = "You can't screw this up"
        } else if requiredOnFinal < 60 {
            status = "In the bag"
        } else if requiredOnFinal < 70 {
            status = "Lite work"
        } else if requiredOnFinal < 80 {
            status = "Good luck!"
        } else if requiredOnFinal < 90 {
            status = "You got this!"
        } else if requiredOnFinal < 100 {
            status = "Better study"
        } else {
            status = "Maybe not"
        }
        
        return (percentage: clampedRequired, status: status)
    }
    
    private func gradeToPercentage(_ grade: String) -> Double {
        let map: [String: Double] = [
            "A": 93.0,
            "A-": 90.0,
            "B+": 87.0,
            "B": 83.0,
            "B-": 80.0,
            "C+": 77.0,
            "C": 73.0,
            "C-": 70.0,
            "D+": 67.0,
            "D": 63.0,
            "D-": 60.0,
            "F": 0.0
        ]
        return map[grade] ?? 90.0
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
