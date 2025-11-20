//
//  SettingsView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

enum SelectedOption {
    case p, s, t, none
}

struct Settings: View {
    @Binding var PrimaryColor: Color
    @Binding var SecondaryColor: Color
    @Binding var TertiaryColor: Color
    @State private var selectedOption: SelectedOption = .none
    
    var isPortrait: Bool
    
    var body: some View {
        VStack{
            Text("Settings")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
            
            Divider()
            
            HStack{
                Text("Primary Color")
                    .font(.system(
                        size: iPad ? 28 : 18,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(PrimaryColor)
                
                Spacer()
                
                CompactColorPicker(
                    selectedColor: $PrimaryColor,
                    isExpanded: Binding(
                        get: { selectedOption == .p },
                        set: { newValue in
                            if newValue {
                                selectedOption = .p
                            } else if selectedOption == .p {
                                selectedOption = .none
                            }
                        }
                    ),
                    isPortrait: isPortrait)
            }
            
            HStack{
                Text("Secondary Color")
                    .font(.system(
                        size: iPad ? 28 : 18,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(PrimaryColor)
                
                Spacer()
                
                CompactColorPicker(
                    selectedColor: $SecondaryColor,
                    isExpanded: Binding(
                        get: { selectedOption == .s },
                        set: { newValue in
                            if newValue {
                                selectedOption = .s
                            } else if selectedOption == .s {
                                selectedOption = .none
                            }
                        }
                    ),
                    isPortrait: isPortrait)
            }
            
            HStack{
                Text("Tertiary Color")
                    .font(.system(
                        size: iPad ? 28 : 18,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(PrimaryColor)
                
                Spacer()
                
                CompactColorPicker(
                    selectedColor: $TertiaryColor,
                    isExpanded: Binding(
                        get: { selectedOption == .t },
                        set: { newValue in
                            if newValue {
                                selectedOption = .t
                            } else if selectedOption == .t {
                                selectedOption = .none
                            }
                        }
                    ),
                    isPortrait: isPortrait)
            }
        }
        .onTapGesture {
            selectedOption = .none
        }
    }
}
