//
//  ColorPicker.swift
//  Schedule
//
//  Created by Andreas Royset on 8/18/25.
//

import Foundation
import SwiftUI

var width = CGFloat(iPad ? 500 : 200)
var height = CGFloat(iPad ? 500 : 350)

struct CompactColorPicker: View {
    @Binding var selectedColor: Color
    @State private var isExpanded = false
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 0
    @State private var opacity: Double = 1.0
    @State private var dragLocation = CGPoint(x: 0, y: 0)
    
    var isPortrait: Bool
    
    var body: some View {
        VStack {
            // Color square button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedColor)
                    .frame(width: width*0.9, height: height*0.07)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded color picker
            if isExpanded {
                VStack(spacing: 12) {
                    colorGridView
                    hueSliderView
                    opacitySliderView
                    simplifiedValuesView
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .shadow(radius: 8)
                .transition(.opacity.combined(with:.scale))
                .onAppear {
                    initializeFromColor()
                }
            }
        }
        .frame(maxWidth: width, maxHeight: height)
    }
    
    // MARK: - Sub Views
    
    private var colorGridView: some View {
        ZStack {
            colorGradientBackground
            colorPickerCircle
        }
    }
    
    private var colorGradientBackground: some View {
        return Rectangle()
            .fill(saturationBrightnessGradient)
            .overlay(blackOverlayGradient)
            .cornerRadius(15)
            .frame(width: width*0.9, height: height*0.5)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.black, lineWidth: 1)
            )
    }
    
    private var saturationBrightnessGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: Color(hue: hue, saturation: 1, brightness: 1), location: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var blackOverlayGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var colorPickerCircle: some View {
        Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 26, height: 26)
            .position(dragLocation)
            .gesture(colorPickerDragGesture)
    }
    
    private var colorPickerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let rect = CGRect(x: 0, y: 0, width: width*0.9, height: height*0.5)
                dragLocation.x = max(15, min(rect.width-15, value.location.x))
                dragLocation.y = max(15, min(rect.height-15, value.location.y))
                
                saturation = (dragLocation.x-15) / (rect.width - 30)
                brightness = 1 - ((dragLocation.y-15) / (rect.height - 30))
                updateColor()
            }
    }
    
    private var hueSliderView: some View {
        Rectangle()
            .fill(hueGradient)
            .frame(width: width*0.9, height: height*0.05)
            .cornerRadius(height*0.025)
            .overlay(hueSliderIndicator)
            .gesture(hueSliderDragGesture)
            .overlay(
                RoundedRectangle(cornerRadius: height*0.025)
                    .stroke(Color.black, lineWidth: 1)
            )
    }
    
    private var hueGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink, .red
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var hueSliderIndicator: some View {
        Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: height*0.05-5, height: height*0.05-5)
            .position(x: CGFloat(hue) * width*0.85 + width*0.025, y: height*0.025)
    }
    
    private var hueSliderDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                hue = max(0, min(1, (min(width*0.9-width*0.025, max(width*0.025, value.location.x))-width*0.025) / (width*0.85)))
                updateColor()
            }
    }
    
    private var opacitySliderView: some View {
        Rectangle()
            .fill(opacityGradient)
            .frame(width: width*0.9, height: height*0.05)
            .cornerRadius(height*0.025)
            .overlay(opacitySliderIndicator)
            .gesture(opacitySliderDragGesture)
            .overlay(
                RoundedRectangle(cornerRadius: height*0.025)
                    .stroke(Color.black, lineWidth: 1)
            )
    }
    
    private var opacityGradient: LinearGradient {
        let uiColor = UIColor($selectedColor.wrappedValue)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return LinearGradient(
            gradient: Gradient(colors: [
                Color(red: red, green: green, blue: blue, opacity: 0),
                Color(red: red, green: green, blue: blue, opacity: 0.5),
                Color(red: red, green: green, blue: blue, opacity: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var opacitySliderIndicator: some View {
        Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: height*0.05-5, height: height*0.05-5)
            .position(x: CGFloat(opacity) * width*0.85 + width*0.025, y: height*0.025)
    }
    
    private var opacitySliderDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                opacity = max(0, min(1, (min(width*0.9-width*0.025, max(width*0.025, value.location.x))-width*0.025) / (width*0.85)))
                updateColor()
            }
    }
    
    private var simplifiedValuesView: some View {
        HStack(spacing: 8) {
            // RGB
            VStack(alignment: .leading, spacing: 2) {
                Text("RGB")
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Text("\(Int(rgbValues.red * 255)), \(Int(rgbValues.green * 255)), \(Int(rgbValues.blue * 255)), \(Int(rgbValues.alpha * 255))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(8)
            .background(Color(.systemGray5))
            .cornerRadius(6)
        }
    }
    
    // MARK: - Computed Properties
    
    private var rgbValues: (red: Double, green: Double, blue: Double, alpha: Double) {
        let uiColor = UIColor(selectedColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
    
    // MARK: - Helper Methods
    
    private func updateColor() {
        selectedColor = Color(hue: hue, saturation: saturation, brightness: brightness).opacity(opacity)
    }
    
    private func updateDragLocation() {
        dragLocation.x = saturation * (width * 0.9 - 30) + 15
        dragLocation.y = (1 - brightness) * (height*0.5 - 30) + 15
    }
    
    private func initializeFromColor() {
        let uiColor = UIColor(selectedColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
        opacity = Double(a)
        updateDragLocation()
    }
}

// Updated Settings view
struct Settings: View {
    @Binding var PrimaryColor: Color
    @Binding var SecondaryColor: Color
    @Binding var TertiaryColor: Color
    
    var isPortrait: Bool
    
    var body: some View {
        VStack{
            Text("Settings")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
            
            Divider()
            
            HStack{
                Text("Primary Color")
                    .font(.system(
                        size: iPad ? 28 : 18,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(
                        PrimaryColor)
                
                Spacer()
                
                CompactColorPicker(selectedColor: $PrimaryColor, isPortrait: isPortrait)
            }
            
            HStack{
                Text("Secondary Color")
                    .font(.system(
                        size: iPad ? 28 : 18,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(
                        PrimaryColor)
                
                Spacer()
                
                CompactColorPicker(selectedColor: $SecondaryColor,isPortrait: isPortrait)
            }
            
            HStack{
                Text("Tertiary Color")
                    .font(.system(
                        size: iPad ? 28 : 18,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .padding(12)
                    .foregroundStyle(
                        PrimaryColor)
                
                Spacer()
                
                CompactColorPicker(selectedColor: $TertiaryColor,isPortrait: isPortrait)
            }
        }
    }
}
