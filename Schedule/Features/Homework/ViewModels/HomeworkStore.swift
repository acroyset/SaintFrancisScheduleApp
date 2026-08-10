//
//  HomeworkStore.swift
//  Schedule
//

import Foundation

@MainActor
final class HomeworkStore: ObservableObject {
    @Published private(set) var items: [HomeworkItem] = []

    private let homeworkKey = "HomeworkItems"
    private let defaults: UserDefaults
    private let syncSideEffects: Bool

    init(
        defaults: UserDefaults = .standard,
        syncSideEffects: Bool = true
    ) {
        self.defaults = defaults
        self.syncSideEffects = syncSideEffects
        load()
    }

    func add(_ item: HomeworkItem) {
        items.append(item)
        save()
        UsageStatsStore.shared.recordItemAction(.create, for: .homework)
    }

    func update(_ item: HomeworkItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
        UsageStatsStore.shared.recordItemAction(.edit, for: .homework)
    }

    func delete(_ item: HomeworkItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        save()
        UsageStatsStore.shared.recordItemAction(.delete, for: .homework)
    }

    func toggleComplete(_ item: HomeworkItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isComplete.toggle()
        items[index].completedAt = items[index].isComplete ? Date() : nil
        save()
        if items[index].isComplete {
            UsageStatsStore.shared.recordItemAction(.complete, for: .homework)
        }
    }

    func incompleteItems(for date: Date) -> [HomeworkItem] {
        let calendar = Calendar.current
        return sorted(
            items.filter {
                !$0.isComplete && calendar.isDate($0.dueDate, inSameDayAs: date)
            }
        )
    }

    func upcomingItems(after date: Date, limit: Int = 3) -> [HomeworkItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return Array(
            sorted(
                items.filter {
                    !$0.isComplete && calendar.startOfDay(for: $0.dueDate) > start
                }
            )
            .prefix(limit)
        )
    }

    func overdueItems(before date: Date) -> [HomeworkItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return sorted(
            items.filter {
                !$0.isComplete && calendar.startOfDay(for: $0.dueDate) < start
            }
        )
    }

    func items(forClass classItem: ClassItem) -> [HomeworkItem] {
        sorted(items.filter { item in
            item.classID == classItem.id ||
                (item.classID == nil && item.className == classItem.name)
        })
    }

    func incompleteCount(forClass classItem: ClassItem) -> Int {
        items.filter { item in
            !item.isComplete &&
                (item.classID == classItem.id ||
                    (item.classID == nil && item.className == classItem.name))
        }.count
    }

    /// Attaches legacy name-only homework to stable class IDs and keeps the
    /// saved display name current when a class is renamed.
    @discardableResult
    func reconcileClassReferences(with classes: [ClassItem]) -> Bool {
        var didChange = false

        for index in items.indices {
            let matchingClass = items[index].classID
                .flatMap { classID in classes.first(where: { $0.id == classID }) }
                ?? classes.first(where: {
                    !$0.name.isEmpty &&
                        $0.name.caseInsensitiveCompare(items[index].className) == .orderedSame
                })

            guard let matchingClass else { continue }

            if items[index].classID != matchingClass.id {
                items[index].classID = matchingClass.id
                didChange = true
            }
            if items[index].className != matchingClass.name {
                items[index].className = matchingClass.name
                didChange = true
            }
        }

        if didChange {
            save()
        }
        return didChange
    }

    private func sorted(_ values: [HomeworkItem]) -> [HomeworkItem] {
        values.sorted { first, second in
            let calendar = Calendar.current
            let firstDay = calendar.startOfDay(for: first.dueDate)
            let secondDay = calendar.startOfDay(for: second.dueDate)
            if firstDay != secondDay { return firstDay < secondDay }
            if first.priority.sortRank != second.priority.sortRank {
                return first.priority.sortRank < second.priority.sortRank
            }
            return first.createdAt < second.createdAt
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: homeworkKey) else { return }

        do {
            items = try JSONDecoder().decode([HomeworkItem].self, from: data)
            if syncSideEffects {
                NotificationManager.shared.scheduleHomeworkNotifications(for: items)
            }
        } catch {
            print("❌ Failed to load homework: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: homeworkKey)
            if syncSideEffects {
                SharedGroup.defaults.set(data, forKey: homeworkKey)
                NotificationManager.shared.scheduleHomeworkNotifications(for: items)
            }
        } catch {
            print("❌ Failed to save homework: \(error)")
        }
    }
}
