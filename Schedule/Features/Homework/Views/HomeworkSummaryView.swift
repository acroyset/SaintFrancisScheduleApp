//
//  HomeworkSummaryView.swift
//  Schedule
//

import SwiftUI

struct HomeworkSummaryView: View {
    @ObservedObject var homeworkStore: HomeworkStore

    let selectedDate: Date
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let iPad: Bool
    let classes: [ClassItem]

    @State private var editingHomework: HomeworkItem?
    @AppStorage(AppFeatureBadge.homework.seenKey) private var didSeeHomeworkBadge = false

    private var dueToday: [HomeworkItem] {
        homeworkStore.incompleteItems(for: selectedDate)
    }

    private var overdue: [HomeworkItem] {
        homeworkStore.overdueItems(before: selectedDate)
    }

    private var upcoming: [HomeworkItem] {
        homeworkStore.upcomingItems(after: selectedDate)
    }

    private var visibleItems: [HomeworkItem] {
        Array((overdue + dueToday + upcoming).prefix(5))
    }

    var body: some View {
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .appThemeFont(.primary, size: iPad ? 17 : 15, weight: .bold)
                    Text(title)
                        .appThemeFont(.secondary, size: iPad ? 18 : 15, weight: .bold)
                        .newBadge(!didSeeHomeworkBadge)
                    Spacer()
                    Text("\(visibleItems.count)")
                        .appThemeFont(.secondary, size: iPad ? 13 : 11, weight: .bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PrimaryColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                .foregroundColor(PrimaryColor)

                VStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        HomeworkRow(
                            item: item,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            iPad: iPad,
                            onToggle: {
                                AppFeatureBadge.markSeen(.homework)
                                homeworkStore.toggleComplete(item)
                            },
                            onEdit: {
                                AppFeatureBadge.markSeen(.homework)
                                editingHomework = item
                            },
                            onDelete: {
                                AppFeatureBadge.markSeen(.homework)
                                homeworkStore.delete(item)
                            }
                        )
                    }
                }
            }
            .padding(iPad ? 16 : 12)
            .background(SecondaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .sheet(item: $editingHomework) { item in
                AddHomeworkView(
                    isPresented: Binding(
                        get: { editingHomework != nil },
                        set: { if !$0 { editingHomework = nil } }
                    ),
                    editingHomework: item,
                    homeworkStore: homeworkStore,
                    classes: classes,
                    currentDate: selectedDate,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
            }
        }
    }

    private var title: String {
        if !overdue.isEmpty { return "Homework Needs Attention" }
        if !dueToday.isEmpty { return Calendar.current.isDateInToday(selectedDate) ? "Homework Due Today" : "Homework Due This Day" }
        return "Upcoming Homework"
    }
}

struct HomeworkRow: View {
    let item: HomeworkItem
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let iPad: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var priorityColor: Color {
        switch item.priority {
        case .low: return .green
        case .normal: return PrimaryColor
        case .high: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .appThemeFont(.primary, size: iPad ? 22 : 19, weight: .semibold)
                    .foregroundColor(item.isComplete ? .green : PrimaryColor.opacity(0.75))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .appThemeFont(.primary, size: iPad ? 17 : 15, weight: .bold)
                        .foregroundColor(PrimaryColor)
                        .lineLimit(1)

                    if item.priority == .high {
                        Image(systemName: item.priority.systemImage)
                            .appThemeFont(.primary, size: 12, weight: .bold)
                            .foregroundColor(priorityColor)
                    }
                }

                HStack(spacing: 6) {
                    Text(item.className)
                    Text("•")
                    Text(dueText)
                }
                .appThemeFont(.secondary, size: iPad ? 13 : 11, weight: .medium)
                .foregroundColor(PrimaryColor.opacity(0.62))

                if !item.details.isEmpty {
                    Text(item.details)
                        .appThemeFont(.secondary, size: iPad ? 13 : 11, weight: .medium)
                        .foregroundColor(PrimaryColor.opacity(0.55))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appThemeFont(.primary, size: iPad ? 18 : 16, weight: .semibold)
                    .foregroundColor(PrimaryColor.opacity(0.42))
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(TertiaryColor.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(item.isComplete ? 0.55 : 1)
    }

    private var dueText: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(item.dueDate) { return "Today" }
        if calendar.isDateInTomorrow(item.dueDate) { return "Tomorrow" }
        if item.isOverdue { return "Overdue" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: item.dueDate)
    }
}
