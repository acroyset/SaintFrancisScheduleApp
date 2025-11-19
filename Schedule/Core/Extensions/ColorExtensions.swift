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
            print("⚠️ Failed to get color components")
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
            print("⚠️ Unexpected color component count: \(components.count)")
            return nil
        }
        
        if includeAlpha {
            let rgba: Int = (Int)(r * 255)<<24 | (Int)(g * 255)<<16 | (Int)(b * 255)<<8 | (Int)(a * 255)
            let hex = String(format:"#%08X", rgba)
            print("🎨 Color to hex: \(hex)")
            return hex
        } else {
            let rgb: Int = (Int)(r * 255)<<16 | (Int)(g * 255)<<8 | (Int)(b * 255)
            let hex = String(format:"#%06X", rgb)
            print("🎨 Color to hex (no alpha): \(hex)")
            return hex
        }
    }
}

extension Color {
    func highContrastTextColor() -> Color {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        // luminance calculation (WCAG)
        let luminance = 0.299*r + 0.587*g + 0.114*b
        return luminance > 0.5 ?
        Color(hue: 0, saturation: 0, brightness: 0.4) :
        Color(hue: 0,saturation: 0,brightness: 0.6)
    }
}
