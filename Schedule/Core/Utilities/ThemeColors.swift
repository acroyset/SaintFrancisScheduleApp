//
//  ThemeColors.swift
//  Schedule
//

import Foundation
import SwiftUI

enum AppFontChoice: String, Codable, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum AppFontRole {
    case primary
    case secondary
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = ThemeColors.defaultTheme
}

extension EnvironmentValues {
    var appTheme: ThemeColors {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

struct ThemeColors: Codable {
    var primary: String
    var secondary: String
    var tertiary: String
    var primaryFont: String
    var secondaryFont: String

    init(
        primary: String,
        secondary: String,
        tertiary: String,
        primaryFont: AppFontChoice = .rounded,
        secondaryFont: AppFontChoice = .rounded
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.primaryFont = primaryFont.rawValue
        self.secondaryFont = secondaryFont.rawValue
    }

    var primaryFontChoice: AppFontChoice {
        get { AppFontChoice(rawValue: primaryFont) ?? .rounded }
        set { primaryFont = newValue.rawValue }
    }

    var secondaryFontChoice: AppFontChoice {
        get { AppFontChoice(rawValue: secondaryFont) ?? .rounded }
        set { secondaryFont = newValue.rawValue }
    }

    func font(_ role: AppFontRole, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let choice = role == .primary ? primaryFontChoice : secondaryFontChoice
        return .system(size: size, weight: weight, design: choice.design)
    }

    func font(_ role: AppFontRole, style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let choice = role == .primary ? primaryFontChoice : secondaryFontChoice
        if let weight {
            return .system(style, design: choice.design, weight: weight)
        }
        return .system(style, design: choice.design)
    }

    static let defaultTheme = ThemeColors(
        primary: "#00A5FFFF",
        secondary: "#00A5FF19",
        tertiary: "#FFFFFFFF"
    )

    static func currentLocalTheme() -> ThemeColors {
        guard let data = UserDefaults.standard.data(forKey: "LocalTheme"),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else {
            return .defaultTheme
        }
        return theme
    }

    static func resetLocalTheme() {
        if let data = try? JSONEncoder().encode(ThemeColors.defaultTheme) {
            UserDefaults.standard.set(data, forKey: "LocalTheme")
            SharedGroup.defaults.set(data, forKey: "ThemeColors")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case tertiary
        case primaryFont
        case secondaryFont
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decodeIfPresent(String.self, forKey: .primary) ?? ThemeColors.defaultTheme.primary
        secondary = try container.decodeIfPresent(String.self, forKey: .secondary) ?? ThemeColors.defaultTheme.secondary
        tertiary = try container.decodeIfPresent(String.self, forKey: .tertiary) ?? ThemeColors.defaultTheme.tertiary
        primaryFont = try container.decodeIfPresent(String.self, forKey: .primaryFont) ?? ThemeColors.defaultTheme.primaryFont
        secondaryFont = try container.decodeIfPresent(String.self, forKey: .secondaryFont) ?? ThemeColors.defaultTheme.secondaryFont
    }
}

private struct AppThemeSizedFontModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    let role: AppFontRole
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(theme.font(role, size: size, weight: weight))
    }
}

private struct AppThemeTextStyleModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    let role: AppFontRole
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(theme.font(role, style: style, weight: weight))
    }
}

extension View {
    func appThemeFont(_ role: AppFontRole, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(AppThemeSizedFontModifier(role: role, size: size, weight: weight))
    }

    func appThemeFont(_ role: AppFontRole, style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(AppThemeTextStyleModifier(role: role, style: style, weight: weight))
    }
}
