//
//  WhatsNewView.swift
//  Schedule
//
//  Extracted from ContentView.swift
//

import SwiftUI

struct WhatsNewView: View {
    @Binding var whatsNewPopup: Bool
    @Binding var tutorial: TutorialState
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let isFirstLaunch: Bool
    
    private let whatsNew = "\n- Second Lunch! <----- !!!\n- Personal Events\n- Bug Fixes"
    
    var body: some View {
        VStack {
            Text("Whats New?")
                .font(.system(
                    size: iPad ? 40 : 30,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
            
            Divider()
            
            Text(whatsNew)
                .font(.system(
                    size: iPad ? 24 : 15,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
                .frame(alignment: .leading)
            
            if isFirstLaunch {
                Button {
                    UserDefaults.standard.set(version, forKey: "LastSeenVersion")
                    tutorial = .Intro
                    whatsNewPopup = false
                } label: {
                    Text("Start Tutorial")
                        .font(.system(
                            size: iPad ? 24 : 15,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .foregroundColor(PrimaryColor)
                        .multilineTextAlignment(.trailing)
                        .padding(12)
                        .background(SecondaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: iPad ? 500 : 300)
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 20)
    }
}
