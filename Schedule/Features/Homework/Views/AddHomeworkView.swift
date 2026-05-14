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
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    @State private var title = ""
    @State private var details = ""
    @State private var selectedClass = ""
    @State private var dueDate = Date()
    @State private var priority: HomeworkPriority = .normal
    @State private var reminderChoice: HomeworkReminderChoice = .nightBefore

    private var classNames: [String] {
        let filtered = classes
            .map(\.name)
            .filter { name in
                let lower = name.lowercased()
                return !name.isEmpty &&
                    !["lunch", "break", "brunch", "student collaboration", "faculty collaboration"].contains(lower)
            }

        var seen: Set<String> = []
        let unique = filtered.filter { seen.insert($0).inserted }
        return unique.isEmpty ? ["Homework"] : unique
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    Picker("Class", selection: $selectedClass) {
                        ForEach(classNames, id: \.self) { className in
                            Text(className).tag(className)
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
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveHomework()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            AppFeatureBadge.markSeen(.homework)
            UsageStatsStore.shared.setCurrentFeature(.homework)
            loadInitialValues()
        }
        .onDisappear {
            UsageStatsStore.shared.setCurrentFeature(nil)
        }
    }

    private func loadInitialValues() {
        guard title.isEmpty else { return }

        if let editingHomework {
            title = editingHomework.title
            details = editingHomework.details
            selectedClass = editingHomework.className
            dueDate = editingHomework.dueDate
            priority = editingHomework.priority
            reminderChoice = editingHomework.reminderChoice
            return
        }

        selectedClass = classNames.first ?? "Homework"
        dueDate = currentDate
    }

    private func saveHomework() {
        if reminderChoice != .none {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editingHomework {
            var updated = editingHomework
            updated.title = trimmedTitle
            updated.details = trimmedDetails
            updated.className = selectedClass
            updated.dueDate = Calendar.current.startOfDay(for: dueDate)
            updated.priority = priority
            updated.reminderChoice = reminderChoice
            homeworkStore.update(updated)
        } else {
            let item = HomeworkItem(
                className: selectedClass,
                title: trimmedTitle,
                details: trimmedDetails,
                dueDate: Calendar.current.startOfDay(for: dueDate),
                priority: priority,
                reminderChoice: reminderChoice,
                isComplete: false,
                createdAt: Date()
            )
            homeworkStore.add(item)
        }

        isPresented = false
        dismiss()
    }
}
