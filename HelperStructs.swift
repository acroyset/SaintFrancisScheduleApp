//
//  Structs.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//
import SwiftUI










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
