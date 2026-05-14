//
//  HomeworkStore.swift
//  Schedule
//

import Foundation

@MainActor
final class HomeworkStore: ObservableObject {
    @Published private(set) var items: [HomeworkItem] = []

    private let homeworkKey = "HomeworkItems"

    init() {
        load()
    }

    func add(_ item: HomeworkItem) {
        items.append(item)
        save()
    }

    func update(_ item: HomeworkItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func delete(_ item: HomeworkItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func toggleComplete(_ item: HomeworkItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isComplete.toggle()
        items[index].completedAt = items[index].isComplete ? Date() : nil
        save()
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

    func items(forClass className: String) -> [HomeworkItem] {
        sorted(items.filter { $0.className == className })
    }

    func incompleteCount(forClass className: String) -> Int {
        items.filter { $0.className == className && !$0.isComplete }.count
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
        guard let data = UserDefaults.standard.data(forKey: homeworkKey) else { return }

        do {
            items = try JSONDecoder().decode([HomeworkItem].self, from: data)
            NotificationManager.shared.scheduleHomeworkNotifications(for: items)
        } catch {
            print("❌ Failed to load homework: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: homeworkKey)
            SharedGroup.defaults.set(data, forKey: homeworkKey)
            NotificationManager.shared.scheduleHomeworkNotifications(for: items)
        } catch {
            print("❌ Failed to save homework: \(error)")
        }
    }
}
