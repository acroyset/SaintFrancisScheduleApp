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
    
    let tools: [(name: String, icon: String)] = [
        ("Home", "house.fill"),
        ("News", "newspaper.fill"),
        ("Edit Classes", "pencil.and.list.clipboard"),
        ("Settings", "gearshape.fill"),
        ("Profile", "person.crop.circle.fill")
    ]
    
    var body: some View {
        HStack {
            ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                ToolButton(
                    window: $window,
                    index: index,
                    icon: tool.icon,
                    label: tool.name,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                    
                )
            }
        }
        .padding(8)
    }
}

struct ToolButton: View {
    @Binding var window: Window
    var index: Int
    var icon: String
    var label: String
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    
    var body: some View {
        let active = window.rawValue == index
        
        let content = Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if let w = Window(rawValue: index) {
                    window = w
                }
            }
        } label: {
            if #available(iOS 26.1, *) {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: iPad ? 24 : 18, weight: .semibold))
                        .foregroundColor(active ? TertiaryColor : PrimaryColor)
                        .scaleEffect(active ? 1.1 : 1.0)
                    
                    if iPad {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(active ? TertiaryColor : PrimaryColor)
                    }
                }
                .padding(6)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: iPad ? 24 : 18, weight: .semibold))
                        .foregroundColor(active ? TertiaryColor : PrimaryColor)
                        .scaleEffect(active ? 1.1 : 1.0)
                    
                    if iPad {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(active ? TertiaryColor : PrimaryColor)
                    }
                }
                .padding(16)
            }

        }
        
        if #available(iOS 26.1, *) {
            content.buttonStyle(GlassButtonStyle(.regular.tint(active ? PrimaryColor : .white)))
        } else {
            content.background(
                ZStack {
                    if active {
                        Capsule()
                            .fill(PrimaryColor)
                    } else {
                        Capsule()
                            .fill(SecondaryColor)
                    }
                }
            )
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
