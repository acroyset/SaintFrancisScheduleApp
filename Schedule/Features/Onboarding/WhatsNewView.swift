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
    
    let whatsNew: String
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text("What’s New?")
                    .font(.system(
                        size: iPad ? 40 : 30,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .foregroundStyle(PrimaryColor)

                Spacer(minLength: 8)

                Button(action: close) {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: iPad ? 28 : 24, weight: .semibold))
                        .foregroundStyle(PrimaryColor)
                }
                .accessibilityLabel("Close What’s New")
            }
            .padding(12)
            
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
        .accessibilityAction(.escape, close)
    }

    private func close() {
        UserDefaults.standard.set(version, forKey: "LastSeenVersion")
        whatsNewPopup = false
    }
}
