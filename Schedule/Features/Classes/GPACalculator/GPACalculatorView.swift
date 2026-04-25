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
    @ObservedObject var localGradeStore: LocalGradeStore
    
    let classTypes = ["Normal", "Honors", "AP"]
    
    func percentageToLetter(_ percentage: Double) -> String {
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

    func gradeToGPA(_ percentage: Double, isHonors: Bool, isAP: Bool) -> Double {
        let letter = percentageToLetter(percentage)
        let baseGPA: [String: Double] = [
            "A": 4.0,  "A-": 3.7,
            "B+": 3.3, "B": 3.0, "B-": 2.7,
            "C+": 2.3, "C": 2.0, "C-": 1.7,
            "D+": 1.3, "D": 1.0, "D-": 0.7,
            "F": 0.0
        ]

        var gpa = baseGPA[letter] ?? 0.0
        if isHonors { gpa += 1.0 }
        if isAP { gpa += 1.0 }
        return min(gpa, 5.0)
    }

    func calculateGPA(isWeighted: Bool) -> Double {
        var totalGPA = 0.0
        var validGradeCount = 0

        for index in 0..<min(7, data.classes.count) {
            let record = localGradeStore.record(for: index, className: data.classes[index].name)
            guard let percentage = Double(record.gpaPercentage),
                  (0...100).contains(percentage) else { continue }

            let isHonors = record.gpaType == "Honors" && isWeighted
            let isAP = record.gpaType == "AP" && isWeighted
            totalGPA += gradeToGPA(percentage, isHonors: isHonors, isAP: isAP)
            validGradeCount += 1
        }

        guard validGradeCount > 0 else { return 0.0 }
        return totalGPA / Double(validGradeCount)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                
                ScrollView {
                    VStack(spacing: 12) {
                        
                        Color.clear.frame(height: iPad ? 60 : 50)
                        
                        VStack(spacing: 10) {
                            gpaSummaryCard(
                                title: "Weighted GPA",
                                subtitle: "Honors and AP included",
                                value: calculateGPA(isWeighted: true)
                            )

                            gpaSummaryCard(
                                title: "Unweighted GPA",
                                subtitle: "No class boosts",
                                value: calculateGPA(isWeighted: false)
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Classes with grade selection
                        VStack(spacing: 12) {
                            ForEach(0..<min(7, data.classes.count), id: \.self) { index in
                                let record = localGradeStore.record(for: index, className: data.classes[index].name)
                                let percentageBinding = localGradeStore.binding(for: index, className: data.classes[index].name, keyPath: \.gpaPercentage)
                                let percentageValue = Double(record.gpaPercentage).flatMap { (0...100).contains($0) ? $0 : nil }

                                VStack(spacing: 8) {
                                    Text(data.classes[index].name.isEmpty ? "Class Name" : data.classes[index].name)
                                        .appThemeFont(.secondary, size: 14, weight: .bold)
                                        .foregroundStyle(PrimaryColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Grade")
                                                .appThemeFont(.secondary, size: 11, weight: .semibold)
                                                .foregroundStyle(PrimaryColor.opacity(0.7))

                                            HStack(spacing: 8) {
                                                TextField("95", text: percentageBinding)
                                                    .keyboardType(.decimalPad)
                                                    .appThemeFont(.secondary, size: 14, weight: .semibold)
                                                    .padding(10)
                                                    .foregroundStyle(PrimaryColor)
                                                    .background(SecondaryColor.opacity(0.8))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                                Text("%")
                                                    .appThemeFont(.secondary, size: 12, weight: .semibold)
                                                    .foregroundStyle(PrimaryColor)
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Type")
                                                .appThemeFont(.secondary, size: 11, weight: .semibold)
                                                .foregroundStyle(PrimaryColor.opacity(0.7))
                                            
                                            Picker("Type", selection: localGradeStore.binding(for: index, className: data.classes[index].name, keyPath: \.gpaType)) {
                                                ForEach(classTypes, id: \.self) { type in
                                                    Text(type).tag(type)
                                                }
                                            }
                                            .tint(PrimaryColor)
                                            .frame(maxWidth: .infinity)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("GPA")
                                                .appThemeFont(.secondary, size: 11, weight: .semibold)
                                                .foregroundStyle(PrimaryColor.opacity(0.7))

                                            if let percentage = percentageValue {
                                                HStack(spacing: 6) {
                                                    Text(percentageToLetter(percentage))
                                                        .appThemeFont(.secondary, size: 13, weight: .bold)
                                                        .foregroundStyle(TertiaryColor)
                                                        .frame(minWidth: 26)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 5)
                                                        .background(PrimaryColor)
                                                        .clipShape(Capsule())

                                                    Text(String(format: "%.2f", gradeToGPA(percentage, isHonors: record.gpaType == "Honors", isAP: record.gpaType == "AP")))
                                                        .appThemeFont(.secondary, size: 14, weight: .bold)
                                                        .foregroundStyle(PrimaryColor)
                                                }
                                            } else {
                                                Text("--")
                                                    .appThemeFont(.secondary, size: 14, weight: .bold)
                                                    .foregroundStyle(PrimaryColor)
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .background(SecondaryColor)
                                .cornerRadius(16)
                                .shadow(radius: 20)
                            }
                        }
                        
                        Text("Your grade data is stored locally on this device. It is not sent to us, and we do not collect it.")
                            .appThemeFont(.secondary, style: .footnote)
                            .foregroundStyle(TertiaryColor.highContrastTextColor())
                        
                    }
                    .padding(16)
                    
                    Color.clear.frame(height: iPad ? 60 : 50)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    hideKeyboard()
                }
                .mask{
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
            }
            
            VStack{
                
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    HStack {
                        Text("GPA Calculator")
                            .appThemeFont(.secondary, size: iPad ? 34 : 22, weight: .bold)
                            .padding(iPad ? 16 : 12)
                            .padding(.horizontal, iPad ? 20 : 16)
                        
                        Spacer()
                        
                        Button(action: { window = .None }) {
                            Image(systemName: "xmark.circle.fill")
                                .appThemeFont(.primary, size: iPad ? 30 : 26)
                                .foregroundStyle(PrimaryColor)
                        }
                        .padding(iPad ? 16 : 12)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(PrimaryColor)
                    .glassEffect()
                } else {
                    HStack {
                        Text("GPA Calculator")
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
    }

    private func gpaSummaryCard(title: String, subtitle: String, value: Double) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appThemeFont(.secondary, size: 13, weight: .bold)
                    .foregroundStyle(PrimaryColor)

                Text(subtitle)
                    .appThemeFont(.secondary, size: 10, weight: .semibold)
                    .foregroundStyle(PrimaryColor.opacity(0.65))
            }

            Spacer()

            Text(String(format: "%.2f", value))
                .appThemeFont(.primary, size: iPad ? 42 : 34, weight: .bold)
                .foregroundStyle(PrimaryColor)
        }
        .padding(16)
        .background(SecondaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
