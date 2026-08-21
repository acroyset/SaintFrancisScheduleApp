import SwiftUI

struct CloudSyncView: View {
    let email: String?
    let schedulePhase: CloudSyncPhase
    let eventsPhase: CloudSyncPhase
    let lastScheduleSync: Date?
    let lastEventsSync: Date?
    let pendingScheduleChanges: Int
    let classCount: Int
    let eventCount: Int
    let primaryColor: Color
    let secondaryColor: Color
    let backgroundColor: Color
    let syncNow: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConnected = NetworkCloudConnectivity.shared.isConnected

    private var overallPhase: CloudSyncPhase {
        guard email != nil else { return .disconnected }
        guard isConnected else {
            return .failed(CloudConnectivityError.offline.localizedDescription)
        }
        if case .failed(let message) = schedulePhase { return .failed(message) }
        if case .failed(let message) = eventsPhase { return .failed(message) }
        if schedulePhase == .loading || eventsPhase == .loading { return .loading }
        if schedulePhase == .pending || eventsPhase == .pending { return .pending }
        return .synced
    }

    private var lastSync: Date? {
        [lastScheduleSync, lastEventsSync].compactMap { $0 }.min()
    }

    private var foreground: Color {
        primaryColor.accessibleForegroundColor(against: backgroundColor)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    dataCard
                    behaviorCard

                    if case .failed(let message) = overallPhase {
                        errorCard(message)
                    }
                }
                .padding(18)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: .cloudConnectivityChanged)) { _ in
                isConnected = NetworkCloudConnectivity.shared.isConnected
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(foreground)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: overallPhase.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(spacing: 5) {
                Text(overallPhase.title)
                    .appThemeFont(.primary, size: 22, weight: .bold)
                    .foregroundStyle(foreground)
                Text(statusDetail)
                    .appThemeFont(.secondary, size: 14)
                    .foregroundStyle(foreground.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            if email != nil {
                Button(action: syncNow) {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .appThemeFont(.primary, size: 15, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(backgroundColor.highContrastTextColor())
                        .background(primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .disabled(overallPhase == .loading)
                .accessibilityIdentifier("cloud.sync-now")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cloudCard(background: secondaryColor)
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Stored in Cloud", icon: "externaldrive.badge.icloud")
            cloudRow("Schedule & theme", detail: "\(classCount) classes", phase: schedulePhase)
            Divider().opacity(0.35)
            cloudRow("Events & reminders", detail: "\(eventCount) items", phase: eventsPhase)
        }
        .padding(16)
        .cloudCard(background: secondaryColor)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("How It Works", icon: "arrow.triangle.2.circlepath.icloud")
            behaviorRow("Saved automatically", "Edits are stored on this device immediately.")
            behaviorRow("Works offline", "Unsent changes wait safely and upload when you reconnect.")
            behaviorRow("Updates everywhere", "Signed-in devices receive changes while the app is open.")
        }
        .padding(16)
        .cloudCard(background: secondaryColor)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sync problem", systemImage: "exclamationmark.triangle.fill")
                .appThemeFont(.primary, size: 15, weight: .bold)
                .foregroundStyle(.red)
            Text(message)
                .appThemeFont(.secondary, size: 13)
                .foregroundStyle(foreground.opacity(0.8))
            Text("Your changes are still saved on this device. Tap Sync Now after reconnecting.")
                .appThemeFont(.secondary, size: 12)
                .foregroundStyle(foreground.opacity(0.65))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .appThemeFont(.primary, size: 15, weight: .bold)
            .foregroundStyle(foreground)
            .padding(.bottom, 12)
    }

    private func cloudRow(
        _ title: String,
        detail: String,
        phase: CloudSyncPhase
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appThemeFont(.secondary, size: 15, weight: .semibold)
                Text(detail)
                    .appThemeFont(.secondary, size: 12)
                    .opacity(0.65)
            }
            .foregroundStyle(foreground)
            Spacer()
            Label(phase.title, systemImage: phase.systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(color(for: phase))
                .accessibilityLabel(phase.title)
        }
        .padding(.vertical, 12)
    }

    private func behaviorRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appThemeFont(.secondary, size: 14, weight: .semibold)
                Text(detail).appThemeFont(.secondary, size: 12).opacity(0.68)
            }
            .foregroundStyle(foreground)
        }
    }

    private var statusDetail: String {
        guard let email else { return "Sign in to keep your data updated across devices." }
        if !isConnected {
            return "No internet connection. Changes stay safely on this device until you reconnect."
        }
        if pendingScheduleChanges > 0 {
            return "\(pendingScheduleChanges) change\(pendingScheduleChanges == 1 ? "" : "s") waiting to upload for \(email)"
        }
        if let lastSync {
            return "Last synced \(lastSync.formatted(.relative(presentation: .named))) • \(email)"
        }
        return email
    }

    private var statusColor: Color { color(for: overallPhase) }

    private func color(for phase: CloudSyncPhase) -> Color {
        switch phase {
        case .disconnected: .secondary
        case .loading, .pending: .orange
        case .synced: .green
        case .failed: .red
        }
    }
}

private extension View {
    func cloudCard(background: Color) -> some View {
        self
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.primary.opacity(0.06))
            }
    }
}
