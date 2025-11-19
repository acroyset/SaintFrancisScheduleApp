//
//  ToolBar.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct ToolBar: View {
    @Binding var window: Window
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    let tools = ["Home", "News", "Clubs", "Edit Classes", "Settings", "Profile"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                    ToolButton(
                        window: $window,
                        index: index,
                        tool: tool,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ToolButton: View {
    @Binding var window: Window
    var index: Int
    var tool: String
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        Button {
            if let w = Window(rawValue: index) {
                window = w
            }
        } label: {
            Text(tool)
                .font(.system(
                    size: iPad ? 32 : 16,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundColor(window.rawValue == index ? TertiaryColor : PrimaryColor)
                .multilineTextAlignment(.trailing)
                .padding(12)
                .background(window.rawValue == index ? PrimaryColor : SecondaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
