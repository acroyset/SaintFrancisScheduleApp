//
//  HomeworkListView.swift
//  Schedule
//

import SwiftUI

struct HomeworkListView: View {
    @ObservedObject var homeworkStore: HomeworkStore
    let classes: [ClassItem]
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let window: Binding<classWindow>

    @State private var showingAddHomework = false
    @State private var editingHomework: HomeworkItem?
    @AppStorage(AppFeatureBadge.homework.seenKey) private var didSeeHomeworkBadge = false

    private var classNames: [String] {
        classes.map(\.name).filter { !$0.isEmpty }
    }

    private var openItems: [HomeworkItem] {
        homeworkStore.items.filter { !$0.isComplete }.sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
            return lhs.priority.sortRank < rhs.priority.sortRank
        }
    }

    private var completedItems: [HomeworkItem] {
        homeworkStore.items.filter(\.isComplete).sorted { lhs, rhs in
            (lhs.completedAt ?? lhs.dueDate) > (rhs.completedAt ?? rhs.dueDate)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    if openItems.isEmpty && completedItems.isEmpty {
                        emptyState
                    } else {
                        section(title: "Open", items: openItems)
                        section(title: "Completed", items: Array(completedItems.prefix(10)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showingAddHomework) {
            AddHomeworkView(
                isPresented: $showingAddHomework,
                editingHomework: nil,
                homeworkStore: homeworkStore,
                classes: classes,
                currentDate: Date(),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(item: $editingHomework) { item in
            AddHomeworkView(
                isPresented: Binding(
                    get: { editingHomework != nil },
                    set: { if !$0 { editingHomework = nil } }
                ),
                editingHomework: item,
                homeworkStore: homeworkStore,
                classes: classes,
                currentDate: Date(),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                window.wrappedValue = .None
            } label: {
                Image(systemName: "chevron.left")
                    .appThemeFont(.primary, size: 18, weight: .bold)
                    .foregroundColor(PrimaryColor)
                    .frame(width: 40, height: 40)
                    .background(SecondaryColor)
                    .clipShape(Circle())
            }

            Text("Homework")
                .appThemeFont(.secondary, size: iPad ? 34 : 22, weight: .bold)
                .foregroundStyle(PrimaryColor)
                .newBadge(!didSeeHomeworkBadge)

            Spacer()

            Button {
                AppFeatureBadge.markSeen(.homework)
                showingAddHomework = true
            } label: {
                Image(systemName: "plus")
                    .appThemeFont(.primary, size: 18, weight: .bold)
                    .foregroundColor(TertiaryColor)
                    .frame(width: 40, height: 40)
                    .background(PrimaryColor)
                    .clipShape(Circle())
            }
            .newBadge(!didSeeHomeworkBadge)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func section(title: String, items: [HomeworkItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .appThemeFont(.secondary, size: 12, weight: .bold)
                    .foregroundStyle(PrimaryColor.opacity(0.65))

                VStack(spacing: 8) {
                    ForEach(items) { item in
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .appThemeFont(.primary, size: 42, weight: .semibold)
                .foregroundColor(PrimaryColor.opacity(0.45))

            Text("No Homework Yet")
                .appThemeFont(.primary, size: iPad ? 24 : 19, weight: .bold)
                .foregroundColor(PrimaryColor)

            Button {
                AppFeatureBadge.markSeen(.homework)
                showingAddHomework = true
            } label: {
                Label("Add Homework", systemImage: "plus")
                    .appThemeFont(.primary, size: 15, weight: .bold)
                    .foregroundColor(TertiaryColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PrimaryColor)
                    .clipShape(Capsule())
            }
            .newBadge(!didSeeHomeworkBadge)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
