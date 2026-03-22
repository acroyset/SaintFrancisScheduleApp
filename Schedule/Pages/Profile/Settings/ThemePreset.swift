//
//  ThemePreset.swift
//  Schedule
//
//  Created by Andreas Royset on 3/22/26.
//

import SwiftUI

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let primaryHex: String
    let secondaryHex: String
    let tertiaryHex: String

    var primary:   Color { Color(hex: primaryHex)   }
    var secondary: Color { Color(hex: secondaryHex) }
    var tertiary:  Color { Color(hex: tertiaryHex)  }

    static let presets: [ThemePreset] = [
        ThemePreset(id: "ocean",      name: "Ocean",      primaryHex: "#00A5FFFF", secondaryHex: "#00A5FF19", tertiaryHex: "#FFFFFFFF"),
        ThemePreset(id: "midnight",   name: "Midnight",   primaryHex: "#00A5FFFF", secondaryHex: "#00A5FF19", tertiaryHex: "#000000FF"),
        ThemePreset(id: "sunset",     name: "Sunset",     primaryHex: "#FF6B35FF", secondaryHex: "#FF6B3519", tertiaryHex: "#FFFFFFFF"),
        ThemePreset(id: "rose",       name: "Rose",       primaryHex: "#FF2D78FF", secondaryHex: "#FF2D7819", tertiaryHex: "#FFFFFFFF"),
        ThemePreset(id: "forest",     name: "Forest",     primaryHex: "#2ECC71FF", secondaryHex: "#2ECC7119", tertiaryHex: "#FFFFFFFF"),
        ThemePreset(id: "lavender",   name: "Lavender",   primaryHex: "#9B59B6FF", secondaryHex: "#9B59B619", tertiaryHex: "#FFFFFFFF"),
        ThemePreset(id: "gold",       name: "Gold",       primaryHex: "#F1A208FF", secondaryHex: "#F1A20819", tertiaryHex: "#FFFFFFFF"),
        ThemePreset(id: "graphite",   name: "Graphite",   primaryHex: "#8E8E93FF", secondaryHex: "#8E8E9319", tertiaryHex: "#000000FF"),
    ]
}
