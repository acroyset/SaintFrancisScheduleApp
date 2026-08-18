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

    var seenKey: String {
        "DidSeeNewBadge.\(rawValue)"
    }

    static func markSeen(_ feature: AppFeatureBadge) {
        UserDefaults.standard.set(true, forKey: feature.seenKey)
    }
}

struct NewBadge: ViewModifier {
    @Environment(\.appTheme) private var theme

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
                    .foregroundStyle(Color(hex: theme.tertiary))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(hex: theme.primary))
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

private struct ToolButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
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

    @State private var toolFrames: [Int: CGRect] = [:]
    @State private var scrubLocationX: CGFloat?
    @State private var displayedToolIndex: Int?

    private var toolbarPadding: CGFloat { iPad ? 14 : 8 }
    private var selectedForegroundColor: Color { TertiaryColor }
    private var selectionAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.82)
    }
    private let coordinateSpaceName = "ToolBarCoordinateSpace"

    var body: some View {
        toolbarButtons
            .frame(maxWidth: .infinity)
            .padding(toolbarPadding)
            .background {
                toolbarBackground
            }
            .overlay {
                highlightedToolbarLabels
                    .padding(toolbarPadding)
                    .mask(alignment: .topLeading) {
                        selectionMask
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(ToolButtonFramePreferenceKey.self) { frames in
                toolFrames = frames
            }
            .onAppear {
                displayedToolIndex = window.rawValue
            }
            .onChange(of: window) { _, newWindow in
                guard scrubLocationX == nil else { return }

                withAnimation(selectionAnimation) {
                    displayedToolIndex = newWindow.rawValue
                }
            }
            .simultaneousGesture(toolbarSelectionGesture, including: .all)
    }

    private var toolbarButtons: some View {
        HStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                ToolButton(
                    icon: tool.icon,
                    label: tool.name,
                    foregroundColor: PrimaryColor,
                    action: {
                        selectTool(at: index)
                    }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ToolButtonFramePreferenceKey.self,
                            value: [
                                index: geo.frame(in: .named(coordinateSpaceName))
                            ]
                        )
                    }
                )
            }
        }
    }

    private var highlightedToolbarLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                ToolButtonLabel(
                    icon: tool.icon,
                    label: tool.name,
                    foregroundColor: selectedForegroundColor
                )
            }
        }
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        if #available(iOS 26.1, *), AppAvailability.liquidGlass {
            liquidGlassSelectionBubble
        } else {
            ZStack(alignment: .topLeading) {
                legacyButtonBackgrounds
                    .padding(toolbarPadding)

                if let frame = selectionBubbleFrame {
                    Capsule()
                        .fill(PrimaryColor)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    private var legacyButtonBackgrounds: some View {
        HStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                ToolButtonLabel(
                    icon: tool.icon,
                    label: tool.name,
                    foregroundColor: .clear
                )
                .background(SecondaryColor, in: Capsule())
            }
        }
    }

    @available(iOS 26.1, *)
    @ViewBuilder
    private var liquidGlassSelectionBubble: some View {
        if let frame = selectionBubbleFrame {
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .glassEffect(
                    .regular.tint(PrimaryColor.opacity(0.9)).interactive(),
                    in: Capsule()
                )
                .position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private var selectionMask: some View {
        if let frame = selectionBubbleFrame {
            Capsule()
                .fill(TertiaryColor)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private var selectionBubbleFrame: CGRect? {
        if let scrubLocationX {
            return interpolatedToolFrame(at: scrubLocationX)
        }
        return toolFrames[displayedToolIndex ?? window.rawValue]
    }

    private var toolbarSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard tool(at: value.location.x) != nil else { return }

                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    scrubLocationX = value.location.x
                }
            }
            .onEnded { value in
                guard let selectedTool = tool(at: value.location.x) else {
                    withAnimation(selectionAnimation) {
                        scrubLocationX = nil
                    }
                    return
                }

                selectTool(at: selectedTool.key)
            }
    }

    private func selectTool(at index: Int) {
        guard let selectedWindow = Window(rawValue: index) else { return }

        withAnimation(selectionAnimation) {
            displayedToolIndex = index
            scrubLocationX = nil
        }

        if window != selectedWindow {
            window = selectedWindow
        }
    }

    private func tool(at xPosition: CGFloat) -> (key: Int, value: CGRect)? {
        let orderedFrames = toolFrames.sorted { $0.value.midX < $1.value.midX }
        guard !orderedFrames.isEmpty else { return nil }

        return orderedFrames.first(where: {
            xPosition >= $0.value.minX && xPosition <= $0.value.maxX
        }) ?? orderedFrames.min(by: {
            abs($0.value.midX - xPosition) < abs($1.value.midX - xPosition)
        })
    }

    private func interpolatedToolFrame(at xPosition: CGFloat) -> CGRect? {
        let orderedFrames = toolFrames.values.sorted { $0.midX < $1.midX }
        guard let firstFrame = orderedFrames.first,
              let lastFrame = orderedFrames.last else { return nil }

        let clampedX = min(max(xPosition, firstFrame.midX), lastFrame.midX)
        guard let upperIndex = orderedFrames.firstIndex(where: { $0.midX >= clampedX }) else {
            return lastFrame
        }

        guard upperIndex > 0 else {
            return CGRect(
                x: clampedX - firstFrame.width / 2,
                y: firstFrame.minY,
                width: firstFrame.width,
                height: firstFrame.height
            )
        }

        let lowerFrame = orderedFrames[upperIndex - 1]
        let upperFrame = orderedFrames[upperIndex]
        let distance = upperFrame.midX - lowerFrame.midX
        let progress = distance > 0 ? (clampedX - lowerFrame.midX) / distance : 0
        let width = lowerFrame.width + (upperFrame.width - lowerFrame.width) * progress
        let height = lowerFrame.height + (upperFrame.height - lowerFrame.height) * progress
        let midY = lowerFrame.midY + (upperFrame.midY - lowerFrame.midY) * progress

        return CGRect(
            x: clampedX - width / 2,
            y: midY - height / 2,
            width: width,
            height: height
        )
    }
}

struct ToolButton: View {
    var icon: String
    var label: String
    var foregroundColor: Color
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ToolButtonLabel(
                icon: icon,
                label: label,
                foregroundColor: foregroundColor
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("toolbar.\(label.lowercased())")
    }
}

private struct ToolButtonLabel: View {
    let icon: String
    let label: String
    let foregroundColor: Color

    private var iconSize: CGFloat { iPad ? 27 : 19 }
    private var labelSize: CGFloat { iPad ? 18 : 16 }

    var body: some View {
        Group {
            if #available(iOS 26.1, *), AppAvailability.liquidGlass {
                labelContent
                    .padding(iPad ? 16 : 12)
                    .frame(
                        minWidth: iPad ? nil : 58,
                        minHeight: iPad ? 68 : 58
                    )
            } else {
                labelContent
                    .padding(iPad ? 22 : 15)
                    .frame(
                        minWidth: iPad ? nil : 58,
                        minHeight: iPad ? 68 : 58
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var labelContent: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .appThemeFont(.primary, size: iconSize, weight: .semibold)

            if iPad {
                Text(label)
                    .appThemeFont(.primary, size: labelSize)
            }
        }
        .foregroundStyle(foregroundColor)
    }
}
