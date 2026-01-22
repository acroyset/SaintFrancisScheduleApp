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
        ZStack{
            
            VStack{
                ScrollView{
                    
                    Color.clear.frame(height: iPad ? 60 : 50)
                    
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
                        Text("Dark Mode")
                            .font(.system(
                                size: iPad ? 28 : 18,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .padding(12)
                            .foregroundStyle(PrimaryColor)
                        
                        Spacer()
                        
                        DarkModeToggle(tertiaryColor: $TertiaryColor)
                            .tint(PrimaryColor)
                            .padding()
                    }
                    
                    Divider()
                    
                    HStack{
                        
                        Text("Enable Nightly Notifications")
                            .font(.system(
                                size: iPad ? 28 : 18,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .padding(12)
                            .foregroundStyle(PrimaryColor)
                        
                        Toggle("", isOn: Binding(
                            get: { NotificationSettings.isEnabled },
                            set: { NotificationSettings.isEnabled = $0 }
                        ))
                        .tint(PrimaryColor)
                        .padding()
                    }
                    
                    DatePicker(selection: Binding(
                        get: { NotificationSettings.time },
                        set: {
                            NotificationSettings.time = $0
                        }
                    ),
                               displayedComponents: .hourAndMinute
                    ){
                        Text("Alert Time")
                            .font(.system(
                                size: iPad ? 28 : 18,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .padding(12)
                            .foregroundStyle(PrimaryColor)
                    }
                    .disabled(!NotificationSettings.isEnabled)
                    
                    Color.clear.frame(height: iPad ? 60 : 50)
                    
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
                if #available(iOS 26.0, *) {
                    Text("Settings")
                        .font(.system(
                            size: iPad ? 34 : 22,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(iPad ? 16 : 12)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(PrimaryColor)
                        .glassEffect()
                } else {
                    Text("Settings")
                        .font(.system(
                            size: iPad ? 34 : 22,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                }
                
                Spacer()
            }
        }
        .onTapGesture {
            selectedOption = .none
        }
    }
}

struct DarkModeToggle: View {
    @Binding var tertiaryColor: Color

    private var isDarkMode: Binding<Bool> {
        Binding(
            get: { tertiaryColor == .black },
            set: { tertiaryColor = $0 ? .black : .white }
        )
    }

    var body: some View {
        Toggle("", isOn: isDarkMode)
    }
}
