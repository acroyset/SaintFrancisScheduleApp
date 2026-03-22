//
//  SettingsView.swift
//  Schedule
//
//  Cleaned up — only settings that actually do something:
//  • Primary colour picker
//  • Secondary colour picker
//  • Dark mode toggle
//  • Nightly notifications toggle
//    - If permission was denied, shows "Open Settings" button instead of toggle
//    - Time picker is ALWAYS enabled (independent of permission status)
//  • Reset to defaults
//

import SwiftUI
import UserNotifications

// MARK: - SelectedOption

enum SelectedOption {
    case p, s, t, none
}

// MARK: - Settings

struct Settings: View {
    @Binding var PrimaryColor:   Color
    @Binding var SecondaryColor: Color
    @Binding var TertiaryColor:  Color

    @State private var selectedOption: SelectedOption = .none
    var isPortrait: Bool

    // Notification permission state
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetAlert = false

    var body: some View {
        ZStack {
            VStack {
                ScrollView {
                    VStack(spacing: 24) {
                        Color.clear.frame(height: iPad ? 60 : 50)

                        // ── Appearance ─────────────────────────────────
                        sectionBlock(title: "Appearance") {
                            colorRow(
                                label: "Primary Color",
                                icon: "circle.lefthalf.filled",
                                color: $PrimaryColor,
                                option: .p
                            )
                            divider()
                            colorRow(
                                label: "Secondary Color",
                                icon: "circle.righthalf.filled",
                                color: $SecondaryColor,
                                option: .s
                            )
                            divider()
                            toggleRow(
                                label: "Dark Mode",
                                icon: "moon.fill",
                                isOn: Binding(
                                    get: { TertiaryColor == .black },
                                    set: { TertiaryColor = $0 ? .black : .white }
                                )
                            )
                        }

                        // ── Notifications ───────────────────────────────
                        sectionBlock(title: "Notifications") {
                            notificationToggleRow()
                            divider()
                            timePickerRow()
                        }

                        // ── Reset ───────────────────────────────────────
                        Button {
                            showResetAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Defaults")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)

                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal)
                }
                .mask {
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.90),
                        .init(color: .clear, location: 1.0)
                    ]), startPoint: .top, endPoint: .bottom)
                }
            }

            // ── Header ─────────────────────────────────────────────────
            VStack {
                if #available(iOS 26.0, *), AppAvailability.liquidGlass {
                    Text("Settings")
                        .font(.system(size: iPad ? 34 : 22, weight: .bold, design: .monospaced))
                        .padding(iPad ? 16 : 12)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(PrimaryColor)
                        .glassEffect()
                } else {
                    Text("Settings")
                        .font(.system(size: iPad ? 34 : 22, weight: .bold, design: .monospaced))
                        .padding(12)
                        .foregroundStyle(PrimaryColor)
                }
                Spacer()
            }
        }
        .onTapGesture { selectedOption = .none }
        .onAppear { refreshPermissionStatus() }
        .alert("Reset Settings?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { resetDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore colors and notification settings to their defaults.")
        }
    }

    // MARK: - Notification rows

    /// The enable/disable toggle — adapts based on system permission status.
    @ViewBuilder
    private func notificationToggleRow() -> some View {
        switch permissionStatus {

        case .denied:
            // Can't prompt again — send user to iOS Settings
            HStack {
                Image(systemName: "bell.slash.fill")
                    .frame(width: 24)
                    .foregroundColor(PrimaryColor)
                    .padding(.leading, 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nightly Notifications")
                        .font(.system(size: iPad ? 18 : 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(PrimaryColor)
                    Text("Permission denied — tap to open Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PrimaryColor)
                        .clipShape(Capsule())
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 14)

        default:
            // .notDetermined, .authorized, .provisional, .ephemeral
            HStack {
                Image(systemName: "bell.fill")
                    .frame(width: 24)
                    .foregroundColor(PrimaryColor)
                    .padding(.leading, 16)
                Text("Nightly Notifications")
                    .font(.system(size: iPad ? 18 : 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(PrimaryColor)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { NotificationSettings.isEnabled },
                    set: { newValue in
                        if newValue {
                            requestNotificationPermission { granted in
                                NotificationSettings.isEnabled = granted
                                refreshPermissionStatus()
                            }
                        } else {
                            NotificationSettings.isEnabled = false
                            NotificationManager.shared.cancelNightlyNotifications()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: PrimaryColor))
                .padding(.trailing, 16)
            }
            .padding(.vertical, 14)
        }
    }

    /// Time picker — ALWAYS active regardless of permission status.
    @ViewBuilder
    private func timePickerRow() -> some View {
        HStack {
            Image(systemName: "clock.badge")
                .frame(width: 24)
                .foregroundColor(PrimaryColor)
                .padding(.leading, 16)
            DatePicker(
                "Alert Time",
                selection: Binding(
                    get: { NotificationSettings.time },
                    set: { NotificationSettings.time = $0 }
                ),
                displayedComponents: .hourAndMinute
            )
            .font(.system(size: iPad ? 18 : 15, weight: .semibold, design: .monospaced))
            .foregroundColor(PrimaryColor)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func refreshPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                permissionStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                // Already granted
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                // Show the system prompt
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        self.refreshPermissionStatus()
                        completion(granted)
                    }
                }
            case .denied:
                // Can't prompt — tell the caller it failed
                DispatchQueue.main.async {
                    self.refreshPermissionStatus()
                    completion(false)
                }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func resetDefaults() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            PrimaryColor   = Color(hex: "#00A5FFFF")
            SecondaryColor = Color(hex: "#00A5FF19")
            TertiaryColor  = Color.white
        }
        NotificationSettings.isEnabled = false
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func sectionBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(PrimaryColor.opacity(0.55))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func divider() -> some View {
        Divider().padding(.leading, 56)
    }

    @ViewBuilder
    private func toggleRow(label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(PrimaryColor)
                .padding(.leading, 16)
            Text(label)
                .font(.system(size: iPad ? 18 : 15, weight: .semibold, design: .monospaced))
                .foregroundColor(PrimaryColor)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: PrimaryColor))
                .padding(.trailing, 16)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func colorRow(label: String, icon: String, color: Binding<Color>, option: SelectedOption) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(PrimaryColor)
                .padding(.leading, 16)
            Text(label)
                .font(.system(size: iPad ? 18 : 15, weight: .semibold, design: .monospaced))
                .foregroundColor(PrimaryColor)
            Spacer()
            CompactColorPicker(
                selectedColor: color,
                isExpanded: Binding(
                    get: { selectedOption == option },
                    set: { newValue in
                        if newValue { selectedOption = option }
                        else if selectedOption == option { selectedOption = .none }
                    }
                ),
                isPortrait: isPortrait
            )
            .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Dark mode toggle (kept for backward compat)
struct DarkModeToggle: View {
    @Binding var tertiaryColor: Color
    private var isDarkMode: Binding<Bool> {
        Binding(get: { tertiaryColor == .black }, set: { tertiaryColor = $0 ? .black : .white })
    }
    var body: some View { Toggle("", isOn: isDarkMode) }
}
