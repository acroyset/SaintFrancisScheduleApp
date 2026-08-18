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
        ClassFeatureHeader(
            title: "Homework",
            PrimaryColor: PrimaryColor,
            SecondaryColor: SecondaryColor,
            TertiaryColor: TertiaryColor,
            onBack: { window.wrappedValue = .None },
            trailingSystemImage: "plus",
            trailingAccessibilityLabel: "Add homework",
            trailingAction: {
                showingAddHomework = true
            }
        )
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
                                homeworkStore.toggleComplete(item)
                            },
                            onEdit: {
                                editingHomework = item
                            },
                            onDelete: {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
