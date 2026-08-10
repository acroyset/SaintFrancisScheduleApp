//
//  ColorExtensions.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation
import SwiftUI

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var int: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&int)

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 8: // RRGGBBAA
            r = Double((int & 0xFF000000) >> 24) / 255
            g = Double((int & 0x00FF0000) >> 16) / 255
            b = Double((int & 0x0000FF00) >> 8) / 255
            a = Double(int & 0x000000FF) / 255
        case 6: // RRGGBB
            r = Double((int & 0xFF0000) >> 16) / 255
            g = Double((int & 0x00FF00) >> 8) / 255
            b = Double(int & 0x0000FF) / 255
            a = 1.0
        default:
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// Replace the Color extension toHex() method in ContentView.swift

extension Color {
    /// Convert a SwiftUI Color into a hex string like "#RRGGBBAA"
    func toHex(includeAlpha: Bool = true) -> String? {
        // Get UIColor from SwiftUI Color
        guard let components = UIColor(self).cgColor.components else {
            print("❌ Failed to get color components")
            return nil
        }
        
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        
        // Handle different color spaces
        switch components.count {
        case 2: // Grayscale
            r = components[0]
            g = components[0]
            b = components[0]
            a = components[1]
        case 4: // RGBA
            r = components[0]
            g = components[1]
            b = components[2]
            a = components[3]
        default:
            print("❌ Unexpected color component count: \(components.count)")
            return nil
        }
        
        if includeAlpha {
            let rgba: Int = (Int)(r * 255)<<24 | (Int)(g * 255)<<16 | (Int)(b * 255)<<8 | (Int)(a * 255)
            let hex = String(format:"#%08X", rgba)
            return hex
        } else {
            let rgb: Int = (Int)(r * 255)<<16 | (Int)(g * 255)<<8 | (Int)(b * 255)
            let hex = String(format:"#%06X", rgb)
            return hex
        }
    }
}

extension Color {
    private func resolvedRGBA() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return (red, green, blue, alpha)
    }

    func luminance() -> CGFloat {
        guard let components = resolvedRGBA() else { return 0.5 }

        // luminance calculation (WCAG)
        return 0.299 * components.red
            + 0.587 * components.green
            + 0.114 * components.blue
    }

    /// WCAG relative luminance for contrast calculations.
    private func relativeLuminance() -> CGFloat {
        guard let components = resolvedRGBA() else { return 0.5 }

        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(components.red)
            + 0.7152 * linearized(components.green)
            + 0.0722 * linearized(components.blue)
    }

    func contrastRatio(with other: Color) -> CGFloat {
        let first = relativeLuminance()
        let second = other.relativeLuminance()
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func composited(over background: Color) -> Color {
        guard let foreground = resolvedRGBA(),
              let background = background.resolvedRGBA() else {
            return self
        }

        let outputAlpha = foreground.alpha + background.alpha * (1 - foreground.alpha)
        guard outputAlpha > 0 else { return .clear }

        return Color(
            red: (foreground.red * foreground.alpha
                + background.red * background.alpha * (1 - foreground.alpha)) / outputAlpha,
            green: (foreground.green * foreground.alpha
                + background.green * background.alpha * (1 - foreground.alpha)) / outputAlpha,
            blue: (foreground.blue * foreground.alpha
                + background.blue * background.alpha * (1 - foreground.alpha)) / outputAlpha,
            opacity: outputAlpha
        )
    }

    /// Preserves the supplied color when it is readable, otherwise blends it
    /// toward black or white just enough to meet the requested contrast.
    func accessibleForegroundColor(
        against background: Color,
        minimumContrast: CGFloat = 4.5
    ) -> Color {
        guard contrastRatio(with: background) < minimumContrast,
              let original = resolvedRGBA() else {
            return self
        }

        let black = Color.black
        let white = Color.white
        let target: (red: CGFloat, green: CGFloat, blue: CGFloat) =
            black.contrastRatio(with: background) >= white.contrastRatio(with: background)
                ? (0, 0, 0)
                : (1, 1, 1)

        func blendedColor(progress: CGFloat) -> Color {
            Color(
                red: original.red + (target.red - original.red) * progress,
                green: original.green + (target.green - original.green) * progress,
                blue: original.blue + (target.blue - original.blue) * progress,
                opacity: original.alpha
            )
        }

        guard blendedColor(progress: 1).contrastRatio(with: background) >= minimumContrast else {
            return black.contrastRatio(with: background) >= white.contrastRatio(with: background)
                ? black
                : white
        }

        var failingProgress: CGFloat = 0
        var passingProgress: CGFloat = 1
        for _ in 0..<16 {
            let candidateProgress = (failingProgress + passingProgress) / 2
            if blendedColor(progress: candidateProgress).contrastRatio(with: background) >= minimumContrast {
                passingProgress = candidateProgress
            } else {
                failingProgress = candidateProgress
            }
        }

        return blendedColor(progress: passingProgress)
    }
}

extension Color {
    func highContrastTextColor() -> Color {
        let luminance = self.luminance()
        return luminance > 0.5 ?
        Color(hue: 0, saturation: 0, brightness: 0.4) :
        Color(hue: 0,saturation: 0,brightness: 0.6)
    }

    func maximumContrastTextColor() -> Color {
        luminance() > 0.5 ? .black : .white
    }
}

extension Color {
    static let eventColors: [Color] = [
        Color(hex: "#FF6B6BFF"), // Red
        Color(hex: "#4ECDC4FF"), // Teal
        Color(hex: "#45B7D1FF"), // Blue
        Color(hex: "#96CEB4FF"), // Green
        Color(hex: "#FFEAA7FF"), // Yellow
        Color(hex: "#DDA0DDFF"), // Plum
        Color(hex: "#FFB347FF"), // Orange
        Color(hex: "#87CEEBFF")  // Sky Blue
    ]
}
