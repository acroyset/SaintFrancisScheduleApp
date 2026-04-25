//
//  ToolBar.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI
import Foundation

enum AppFeatureBadge: String {
    case profileTab
    case classesTab
    case settings
    case fontPicker
    case whatIfCalculator
}

struct NewBadge: ViewModifier {
    let isShown: Bool
    private let overhang: CGFloat = 4

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content
                .padding(.top, overhang)
                .padding(.trailing, overhang)

            if isShown {
                Text("NEW")
                    .appThemeFont(.secondary, style: .caption2, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: overhang, y: -overhang)
            }
        }
    }
}


extension View {
    func newBadge(_ isShown: Bool = true) -> some View {
        modifier(NewBadge(isShown: isShown))
    }
}

struct ToolBar: View {
    @Binding var window: Window
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    let tools: [(name: String, icon: String)] = [
        ("Home", "house.fill"),
        ("News", "newspaper.fill"),
        ("Classes", "pencil.and.list.clipboard"),
        ("Map", "map.fill"),
        ("Profile", "person.crop.circle.fill")
    ]

    private var toolbarPadding: CGFloat { iPad ? 14 : 8 }
    
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
        .padding(toolbarPadding)
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
        let iconSize: CGFloat = iPad ? 28 : 18
        let labelSize: CGFloat = iPad ? 18 : 16
        let contentPadding: CGFloat = iPad ? 20 : 13
        let glassPadding: CGFloat = iPad ? 10 : 6
        
        let content = Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if let w = Window(rawValue: index) {
                    window = w
                }
            }
        } label: {
            if #available(iOS 26.1, *), AppAvailability.liquidGlass {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .appThemeFont(.primary, size: iconSize, weight: .semibold)
                        .foregroundColor(active ? TertiaryColor : PrimaryColor)
                        .scaleEffect(active ? 1.1 : 1.0)
                     
                    if iPad {
                        Text(label)
                            .appThemeFont(.primary, size: labelSize)
                            .foregroundColor(active ? TertiaryColor : PrimaryColor)
                    }
                }
                .padding(glassPadding)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .appThemeFont(.primary, size: iconSize, weight: .semibold)
                        .foregroundColor(active ? TertiaryColor : PrimaryColor)
                        .scaleEffect(active ? 1.1 : 1.0)
                    
                    if iPad {
                        Text(label)
                            .appThemeFont(.primary, size: labelSize)
                            .foregroundColor(active ? TertiaryColor : PrimaryColor)
                    }
                }
                .padding(contentPadding)
            }

        }
        
        if #available(iOS 26.1, *), AppAvailability.liquidGlass {
            content.buttonStyle(GlassButtonStyle(.regular.tint(active ? PrimaryColor.opacity(0.9) : .clear)))
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
