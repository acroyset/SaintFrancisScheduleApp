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

    private var key: String { "featureBadgeSeen.\(rawValue)" }

    var isVisible: Bool {
        !UserDefaults.standard.bool(forKey: key)
    }

    func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
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
        let isNew = switch Window(rawValue: index) {
        case .Profile: AppFeatureBadge.profileTab.isVisible
        case .ClassesView: AppFeatureBadge.classesTab.isVisible
        default: false
        }
        
        let content = Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if let w = Window(rawValue: index) {
                    switch w {
                    case .Profile:
                        AppFeatureBadge.profileTab.markSeen()
                    case .ClassesView:
                        AppFeatureBadge.classesTab.markSeen()
                    default:
                        break
                    }
                    window = w
                }
            }
        } label: {
            if #available(iOS 26.1, *), AppAvailability.liquidGlass {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .appThemeFont(.primary, size: iPad ? 24 : 18, weight: .semibold)
                        .foregroundColor(active ? TertiaryColor : PrimaryColor)
                        .scaleEffect(active ? 1.1 : 1.0)
                     
                    if iPad || active {
                        Text(label)
                            .appThemeFont(.primary, size: 16)
                            .foregroundColor(active ? TertiaryColor : PrimaryColor)
                    }
                }
                .padding(6)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .appThemeFont(.primary, size: iPad ? 24 : 18, weight: .semibold)
                        .foregroundColor(active ? TertiaryColor : PrimaryColor)
                        .scaleEffect(active ? 1.1 : 1.0)
                    
                    if iPad || active {
                        Text(label)
                            .appThemeFont(.primary, size: 16)
                            .foregroundColor(active ? TertiaryColor : PrimaryColor)
                    }
                }
                .padding(16)
            }

        }
        .newBadge(isNew)
        
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
