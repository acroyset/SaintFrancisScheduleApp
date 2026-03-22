//
//  CompactColorPicker.swift
//  Schedule
//
//  Rewritten — sliders now respond correctly to both taps and drags.
//  Key fix: use a full-width tap/drag target with coordinateSpace so
//  any touch anywhere on the track registers immediately.
//

import SwiftUI

// MARK: - Reliable Track Slider

/// A horizontal slider that responds to taps AND drags anywhere on the track.
/// The previous version used GeometryReader + DragGesture but the hot-area was
/// limited to the tiny indicator circle, making it feel broken.
private struct TrackSlider: View {
    @Binding var value: Double   // 0…1
    let gradient: LinearGradient
    let thumbColor: Color

    // Provide explicit size so the parent can size us consistently
    var trackHeight: CGFloat = 28
    var cornerRadius: CGFloat = 14

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width
            let thumbX = CGFloat(value) * (trackW - trackHeight) + trackHeight / 2

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(gradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.black.opacity(0.25), lineWidth: 1)
                    )

                // Thumb
                Circle()
                    .fill(thumbColor)
                    .frame(width: trackHeight - 4, height: trackHeight - 4)
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            // Full-track gesture — tap anywhere to jump, then drag freely
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let raw = gesture.location.x / trackW
                        value = max(0, min(1, Double(raw)))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: trackHeight)
    }
}

// MARK: - Saturation/Brightness 2-D Picker

private struct SBPicker: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let thumbX = CGFloat(saturation) * w
            let thumbY = (1 - CGFloat(brightness)) * h

            ZStack {
                // Saturation axis
                LinearGradient(
                    gradient: Gradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)]),
                    startPoint: .leading, endPoint: .trailing
                )
                // Brightness axis overlay
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black]),
                    startPoint: .top, endPoint: .bottom
                )

                // Thumb
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .frame(width: isDragging ? 28 : 22, height: isDragging ? 28 : 22)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .position(x: thumbX, y: thumbY)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.3), lineWidth: 1))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        saturation  = max(0, min(1, Double(gesture.location.x / w)))
                        brightness  = max(0, min(1, 1 - Double(gesture.location.y / h)))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
    }
}

// MARK: - CompactColorPicker

struct CompactColorPicker: View {
    @Binding var selectedColor: Color
    @Binding var isExpanded: Bool
    var isPortrait: Bool

    // Internal HSBA state — derived from selectedColor on expansion
    @State private var hue:        Double = 0
    @State private var saturation: Double = 0.8
    @State private var brightness: Double = 0.9
    @State private var opacity:    Double = 1.0

    // Build the current color from sliders
    private var currentColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness).opacity(opacity)
    }

    // Gradient for the hue track
    private var hueGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }),
            startPoint: .leading, endPoint: .trailing
        )
    }

    // Gradient for the opacity track (shows current hue fading)
    private var opacityGradient: LinearGradient {
        let base = Color(hue: hue, saturation: saturation, brightness: brightness)
        return LinearGradient(
            gradient: Gradient(colors: [base.opacity(0), base]),
            startPoint: .leading, endPoint: .trailing
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Swatch button ──────────────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedColor)
                    .frame(width: 120, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: selectedColor.opacity(0.4), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            // ── Expanded panel ─────────────────────────────────────────
            if isExpanded {
                VStack(spacing: 16) {

                    // 2-D Saturation / Brightness picker
                    SBPicker(hue: hue, saturation: $saturation, brightness: $brightness)
                        .frame(height: iPad ? 200 : 150)
                        .onChange(of: saturation) { _, _ in push() }
                        .onChange(of: brightness)  { _, _ in push() }

                    // Hue slider
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hue")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        TrackSlider(
                            value: $hue,
                            gradient: hueGradient,
                            thumbColor: Color(hue: hue, saturation: 1, brightness: 1)
                        )
                        .onChange(of: hue) { _, _ in push() }
                    }

                    // Opacity slider
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opacity")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        TrackSlider(
                            value: $opacity,
                            gradient: opacityGradient,
                            thumbColor: currentColor
                        )
                        .onChange(of: opacity) { _, _ in push() }
                    }

                    // Live preview + hex readout
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentColor)
                            .frame(width: 44, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                        Text(hexString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)

                        Spacer()
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray6))
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                .onAppear { pull() }
            }
        }
        .frame(maxWidth: iPad ? 460 : 300)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // ── Sync helpers ───────────────────────────────────────────────────

    /// Push slider values → selectedColor
    private func push() {
        selectedColor = currentColor
    }

    /// Pull selectedColor → slider values
    private func pull() {
        let ui = UIColor(selectedColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue        = Double(h)
        saturation = Double(s)
        brightness = Double(b)
        opacity    = Double(a)
    }

    private var hexString: String {
        let ui = UIColor(currentColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X %d%%",
                      Int(r*255), Int(g*255), Int(b*255), Int(a*100))
    }
}
