//
//  AddReminderView.swift
//  Schedule
//

import SwiftUI
import UserNotifications

enum ReminderFormValidation {
    static func canSave(
        title: String,
        hasSelectedOffsets: Bool,
        wasSavedWithoutNotifications: Bool,
        isRequestingAuthorization: Bool
    ) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (hasSelectedOffsets || wasSavedWithoutNotifications) &&
            !isRequestingAuthorization
    }
}

struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool

    let editingReminder: CustomEvent?
    let eventsManager: CustomEventsManager
    let currentDate: Date
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    @State private var title = ""
    @State private var note = ""
    @State private var selectedColor = Color.eventColors.first!
    @State private var selectedDate = Date()
    @State private var reminderTime = Time(h: 8, m: 0, s: 0)
    @State private var selectedOffsets: Set<ReminderOffset> = [.tenMinutes]
    @State private var didRecordOpen = false
    @State private var isRequestingAuthorization = false
    @State private var showNotificationsDisabledAlert = false

    private var isSaveEnabled: Bool {
        ReminderFormValidation.canSave(
            title: title,
            hasSelectedOffsets: !selectedOffsets.isEmpty,
            wasSavedWithoutNotifications: editingReminder?.reminderOffsets.isEmpty == true,
            isRequestingAuthorization: isRequestingAuthorization
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Reminder") {
                    TextField("Reminder title", text: $title)

                    HStack {
                        Text("Notes")
                        Spacer()
                        TextField("Optional", text: $note)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("When") {
                    DatePicker(
                        "Day",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )

                    DatePicker(
                        "Time",
                        selection: Binding<Date>(
                            get: { reminderTime.toDate(on: selectedDate) },
                            set: { reminderTime = Time.fromDate($0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                Section("Remind Me") {
                    ForEach(ReminderOffset.allCases) { offset in
                        Button {
                            toggle(offset)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(offset.title)
                                        .foregroundColor(PrimaryColor)
                                    if offset == .oneDay {
                                        Text("Great for an easy day-before heads-up")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if selectedOffsets.contains(offset) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(PrimaryColor)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(PrimaryColor.opacity(0.35))
                                }
                            }
                        }
                    }

                    if !selectedOffsets.isEmpty {
                        Text(selectedSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                ReminderColorSection(selectedColor: $selectedColor, PrimaryColor: PrimaryColor)
            }
            .navigationTitle(editingReminder == nil ? "Add Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        dismiss()
                    }
                    .accessibilityLabel("Cancel reminder")
                    .accessibilityIdentifier("add-reminder.cancel")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveReminder() }
                    }
                    .disabled(!isSaveEnabled)
                    .accessibilityLabel("Save reminder")
                    .accessibilityIdentifier("add-reminder.save")
                }
            }
        }
        .onAppear {
            UsageStatsStore.shared.setCurrentFeature(.reminders)
            recordOpenIfNeeded()
            loadExistingReminder()
        }
        .onDisappear {
            UsageStatsStore.shared.setCurrentFeature(nil)
        }
        .alert("Notifications Disabled", isPresented: $showNotificationsDisabledAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Save Without Notifications") {
                persistReminder(offsets: [])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This reminder cannot alert you unless notifications are enabled in Settings.")
        }
    }

    private var selectedSummary: String {
        selectedOffsets
            .sorted { $0.secondsBefore > $1.secondsBefore }
            .map(\.title)
            .joined(separator: " • ")
    }

    private func toggle(_ offset: ReminderOffset) {
        if selectedOffsets.contains(offset) {
            selectedOffsets.remove(offset)
        } else {
            selectedOffsets.insert(offset)
        }
    }

    private func loadExistingReminder() {
        guard let reminder = editingReminder else {
            selectedDate = currentDate
            return
        }

        title = reminder.title
        note = reminder.note
        selectedColor = Color(hex: reminder.color)
        selectedOffsets = Set(reminder.reminderOffsets)

        if let reminderDate = reminder.firstApplicableDate {
            selectedDate = reminderDate
        } else {
            selectedDate = currentDate
        }

        reminderTime = reminder.startTime
    }

    private func recordOpenIfNeeded() {
        guard editingReminder != nil, !didRecordOpen else { return }
        didRecordOpen = true
        UsageStatsStore.shared.recordItemAction(.open, for: .reminder)
    }

    private func saveReminder() async {
        guard !selectedOffsets.isEmpty else {
            persistReminder(offsets: [])
            return
        }

        isRequestingAuthorization = true
        let isAuthorized = await NotificationManager.shared.ensureNotificationAuthorization()
        isRequestingAuthorization = false

        guard isAuthorized else {
            showNotificationsDisabledAlert = true
            return
        }

        persistReminder(offsets: selectedOffsets.sorted { $0.secondsBefore < $1.secondsBefore })
    }

    private func persistReminder(offsets: [ReminderOffset]) {

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"

        let endTime = Time(seconds: min(reminderTime.seconds + 300, 23 * 3600 + 59 * 60 + 59))

        if let editingReminder {
            let updatedReminder = CustomEvent(
                id: editingReminder.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: reminderTime,
                endTime: endTime,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                color: selectedColor.toHex() ?? "#FF6B6BFF",
                repeatPattern: .none,
                kind: .reminder,
                reminderOffsets: offsets,
                applicableDays: [formatter.string(from: selectedDate)]
            )
            eventsManager.updateEventSync(updatedReminder)
        } else {
            let newReminder = CustomEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: reminderTime,
                endTime: endTime,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                color: selectedColor.toHex() ?? "#FF6B6BFF",
                repeatPattern: .none,
                kind: .reminder,
                reminderOffsets: offsets,
                applicableDays: [formatter.string(from: selectedDate)]
            )
            eventsManager.addEventSync(newReminder)
        }

        isPresented = false
        dismiss()
    }

}

private struct ReminderColorSection: View {
    @Binding var selectedColor: Color
    let PrimaryColor: Color

    var body: some View {
        Section("Color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Color.eventColors, id: \.description) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(PrimaryColor, lineWidth: selectedColor == color ? 3 : 0)
                            )
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
