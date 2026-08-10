//
//  AddHomeworkView.swift
//  Schedule
//

import SwiftUI
import UserNotifications

struct AddHomeworkView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool

    let editingHomework: HomeworkItem?
    let homeworkStore: HomeworkStore
    let classes: [ClassItem]
    let currentDate: Date
    let initialClassName: String?
    let initialClassID: UUID?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    init(
        isPresented: Binding<Bool>,
        editingHomework: HomeworkItem?,
        homeworkStore: HomeworkStore,
        classes: [ClassItem],
        currentDate: Date,
        initialClassName: String? = nil,
        initialClassID: UUID? = nil,
        PrimaryColor: Color,
        SecondaryColor: Color,
        TertiaryColor: Color
    ) {
        _isPresented = isPresented
        self.editingHomework = editingHomework
        self.homeworkStore = homeworkStore
        self.classes = classes
        self.currentDate = currentDate
        self.initialClassName = initialClassName
        self.initialClassID = initialClassID
        self.PrimaryColor = PrimaryColor
        self.SecondaryColor = SecondaryColor
        self.TertiaryColor = TertiaryColor
    }

    @State private var title = ""
    @State private var details = ""
    @State private var selectedClassID: UUID?
    @State private var dueDate = Date()
    @State private var priority: HomeworkPriority = .normal
    @State private var reminderChoice: HomeworkReminderChoice = .nightBefore
    @State private var didRecordOpen = false
    @State private var isRequestingAuthorization = false
    @State private var showNotificationsDisabledAlert = false

    private var availableClasses: [ClassItem] {
        classes.filter { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty &&
                !["lunch", "break", "brunch", "student collaboration", "faculty collaboration"]
                    .contains(name.lowercased())
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (selectedClassID != nil || availableClasses.isEmpty)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Assignment") {
                    TextField("Homework title", text: $title)

                    HStack {
                        Text("Details")
                        Spacer()
                        TextField("Optional", text: $details)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Class") {
                    Picker("Class", selection: $selectedClassID) {
                        if availableClasses.isEmpty {
                            Text("Homework").tag(Optional<UUID>.none)
                        } else {
                            ForEach(availableClasses) { classItem in
                                Text(classItem.name).tag(Optional(classItem.id))
                            }
                        }
                    }
                }

                Section("Due") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

                    Picker("Priority", selection: $priority) {
                        ForEach(HomeworkPriority.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                }

                Section("Reminder") {
                    ForEach(HomeworkReminderChoice.allCases) { choice in
                        Button {
                            reminderChoice = choice
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title)
                                        .foregroundColor(PrimaryColor)
                                    Text(choice.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: reminderChoice == choice ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(reminderChoice == choice ? PrimaryColor : PrimaryColor.opacity(0.35))
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingHomework == nil ? "Add Homework" : "Edit Homework")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        dismiss()
                    }
                    .accessibilityLabel("Cancel homework")
                    .accessibilityIdentifier("add-homework.cancel")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveHomework() }
                    }
                    .disabled(!isValid || isRequestingAuthorization)
                    .accessibilityLabel("Save homework")
                    .accessibilityIdentifier("add-homework.save")
                }
            }
        }
        .onAppear {
            UsageStatsStore.shared.setCurrentFeature(.homework)
            recordOpenIfNeeded()
            loadInitialValues()
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
            Button("Save Without Reminder") {
                reminderChoice = .none
                persistHomework(reminderChoice: .none)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This homework cannot alert you unless notifications are enabled in Settings.")
        }
    }

    private func loadInitialValues() {
        guard title.isEmpty else { return }

        if let editingHomework {
            title = editingHomework.title
            details = editingHomework.details
            selectedClassID = editingHomework.classID
                ?? availableClasses.first(where: {
                    $0.name.caseInsensitiveCompare(editingHomework.className) == .orderedSame
                })?.id
            dueDate = editingHomework.dueDate
            priority = editingHomework.priority
            reminderChoice = editingHomework.reminderChoice
            return
        }

        if let initialClassID,
           availableClasses.contains(where: { $0.id == initialClassID }) {
            selectedClassID = initialClassID
        } else if let initialClassName,
                  let matchingClass = availableClasses.first(where: { $0.name == initialClassName }) {
            selectedClassID = matchingClass.id
        } else {
            selectedClassID = availableClasses.first?.id
        }
        dueDate = currentDate
    }

    private func recordOpenIfNeeded() {
        guard editingHomework != nil, !didRecordOpen else { return }
        didRecordOpen = true
        UsageStatsStore.shared.recordItemAction(.open, for: .homework)
    }

    private func saveHomework() async {
        if reminderChoice != .none {
            isRequestingAuthorization = true
            let isAuthorized = await NotificationManager.shared.ensureNotificationAuthorization()
            isRequestingAuthorization = false

            guard isAuthorized else {
                showNotificationsDisabledAlert = true
                return
            }
        }

        persistHomework(reminderChoice: reminderChoice)
    }

    private func persistHomework(reminderChoice savedReminderChoice: HomeworkReminderChoice) {

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedClass = availableClasses.first(where: { $0.id == selectedClassID })
        let selectedClassName = selectedClass?.name ?? "Homework"

        if let editingHomework {
            var updated = editingHomework
            updated.title = trimmedTitle
            updated.details = trimmedDetails
            updated.className = selectedClassName
            updated.classID = selectedClass?.id
            updated.dueDate = Calendar.current.startOfDay(for: dueDate)
            updated.priority = priority
            updated.reminderChoice = savedReminderChoice
            homeworkStore.update(updated)
        } else {
            let item = HomeworkItem(
                className: selectedClassName,
                classID: selectedClass?.id,
                title: trimmedTitle,
                details: trimmedDetails,
                dueDate: Calendar.current.startOfDay(for: dueDate),
                priority: priority,
                reminderChoice: savedReminderChoice,
                isComplete: false,
                createdAt: Date()
            )
            homeworkStore.add(item)
        }

        isPresented = false
        dismiss()
    }
}
