//
//  ClassEditor.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation
import SwiftUI

struct VphoneClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var isPortrait: Bool
    
    @Binding var window: classWindow
    
    var body: some View {
        VStack{
            
            HStack {
                Text("Class Editor")
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
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            ScrollView {
                VStack(spacing: 12) {
                    
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
        }
    }
}

// MARK: - HphoneClassEditor
struct HphoneClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    @Binding var window: classWindow
    
    var body: some View {
        VStack {
            HStack {
                Text("Class Editor")
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
}
