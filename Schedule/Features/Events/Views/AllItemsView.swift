//
//  AllItemsView.swift
//  Schedule
//

import SwiftUI

private enum AllItemsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case events = "Events"
    case reminders = "Reminders"

    var id: String { rawValue }
}

private enum AllItemsSort: String, CaseIterable, Identifiable {
    case soonest = "Soonest"
    case alphabetical = "A-Z"

    var id: String { rawValue }
}

private struct AllItemsEntry: Identifiable {
    let event: CustomEvent
    let nextOccurrence: Date?
    let fallbackOccurrence: Date?

    var id: UUID { event.id }
}

struct AllItemsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventsManager: CustomEventsManager

    let scheduleDict: [String: [String]]?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    @State private var searchText = ""
    @State private var filter: AllItemsFilter = .all
    @State private var sort: AllItemsSort = .soonest
    @State private var editingEvent: CustomEvent?
    @State private var editingReminder: CustomEvent?

    var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            itemRow(for: entry)
                                .listRowBackground(SecondaryColor.opacity(0.3))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) {
                                        eventsManager.deleteEvent(entry.event)
                                    }

                                    Button("Edit") {
                                        openEditor(for: entry.event)
                                    }
                                    .tint(PrimaryColor)
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(TertiaryColor.ignoresSafeArea())
                }
            }
            .navigationTitle("Events & Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search events and reminders")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(AllItemsFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }

                        Picker("Sort", selection: $sort) {
                            ForEach(AllItemsSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(PrimaryColor)
                    }
                }
            }
        }
        .tint(PrimaryColor)
        .background(TertiaryColor.ignoresSafeArea())
        .onAppear {
            eventsManager.purgeExpiredReminders()
        }
        .sheet(item: $editingEvent) { event in
            AddEventView(
                isPresented: Binding(
                    get: { editingEvent != nil },
                    set: { if !$0 { editingEvent = nil } }
                ),
                editingEvent: event,
                eventsManager: eventsManager,
                currentDayCode: "",
                currentDate: preferredDate(for: event),
                scheduleLines: [],
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(item: $editingReminder) { reminder in
            AddReminderView(
                isPresented: Binding(
                    get: { editingReminder != nil },
                    set: { if !$0 { editingReminder = nil } }
                ),
                editingReminder: reminder,
                eventsManager: eventsManager,
                currentDate: preferredDate(for: reminder),
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
    }

    private var entries: [AllItemsEntry] {
        let referenceDate = Date()
        return eventsManager.events.map { event in
            AllItemsEntry(
                event: event,
                nextOccurrence: nextUpcomingOccurrence(for: event, from: referenceDate),
                fallbackOccurrence: fallbackDisplayDate(for: event)
            )
        }
    }

    private var filteredEntries: [AllItemsEntry] {
        entries
            .filter(matchesFilter)
            .filter(matchesSearch)
            .sorted(by: compareEntries)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .appThemeFont(.primary, size: 34, weight: .semibold)
                .foregroundStyle(PrimaryColor.opacity(0.7))

            Text(emptyTitle)
                .appThemeFont(.primary, size: 24, weight: .bold)
                .foregroundStyle(PrimaryColor)

            Text(emptySubtitle)
                .appThemeFont(.secondary, size: 14, weight: .medium)
                .foregroundStyle(PrimaryColor.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TertiaryColor.ignoresSafeArea())
    }

    private var emptyTitle: String {
        if eventsManager.events.isEmpty {
            return "No Items Yet"
        }

        return "No Matches"
    }

    private var emptySubtitle: String {
        if eventsManager.events.isEmpty {
            return "Create an event or reminder from Home, then manage everything here."
        }

        return "Try a different search or adjust the filter."
    }

    private func itemRow(for entry: AllItemsEntry) -> some View {
        let event = entry.event
        let accent = Color(hex: event.color)

        return Button {
            openEditor(for: event)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent)
                    .frame(width: 8, height: 54)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(event.title)
                            .appThemeFont(.primary, size: 18, weight: .bold)
                            .foregroundStyle(PrimaryColor)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        kindBadge(for: event)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(dateLabel(for: entry))
                    }
                    .appThemeFont(.secondary, size: 13, weight: .medium)
                    .foregroundStyle(PrimaryColor.opacity(0.7))

                    if let timeLabel = timeLabel(for: event) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                            Text(timeLabel)
                        }
                        .appThemeFont(.secondary, size: 13, weight: .medium)
                        .foregroundStyle(PrimaryColor.opacity(0.7))
                    }

                    if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(event.location)
                        }
                        .appThemeFont(.secondary, size: 13, weight: .medium)
                        .foregroundStyle(PrimaryColor.opacity(0.7))
                    }

                    if !event.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(event.note)
                            .appThemeFont(.secondary, size: 13, weight: .medium)
                            .foregroundStyle(PrimaryColor.opacity(0.72))
                            .lineLimit(2)
                    }

                    if event.isReminder && !event.reminderSummary.isEmpty {
                        Text(event.reminderSummary)
                            .appThemeFont(.secondary, size: 12, weight: .semibold)
                            .foregroundStyle(accent.opacity(0.95))
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func kindBadge(for event: CustomEvent) -> some View {
        Text(event.isReminder ? "Reminder" : "Event")
            .appThemeFont(.secondary, size: 11, weight: .bold)
            .foregroundStyle(event.isReminder ? Color.orange : PrimaryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill((event.isReminder ? Color.orange : PrimaryColor).opacity(0.12))
            )
    }

    private func timeLabel(for event: CustomEvent) -> String? {
        if event.isReminder {
            return event.startTime.string()
        }

        return "\(event.startTime.string()) - \(event.endTime.string())"
    }

    private func dateLabel(for entry: AllItemsEntry) -> String {
        if let nextOccurrence = entry.nextOccurrence {
            return DateFormatter.eventDate.string(from: nextOccurrence)
        }

        if let fallbackOccurrence = entry.fallbackOccurrence {
            if entry.event.repeatPattern == .none {
                return DateFormatter.eventDate.string(from: fallbackOccurrence)
            }
        }

        if entry.event.repeatPattern == .none {
            return "No date"
        }

        return entry.event.repeatPattern.description
    }

    private func matchesFilter(_ entry: AllItemsEntry) -> Bool {
        switch filter {
        case .all:
            return true
        case .events:
            return !entry.event.isReminder
        case .reminders:
            return entry.event.isReminder
        }
    }

    private func matchesSearch(_ entry: AllItemsEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let haystack = [
            entry.event.title,
            entry.event.note,
            entry.event.location,
            entry.event.repeatPattern.description,
            entry.event.isReminder ? "reminder" : "event"
        ]
        .joined(separator: " ")
        .localizedLowercase

        return haystack.contains(query.localizedLowercase)
    }

    private func compareEntries(_ lhs: AllItemsEntry, _ rhs: AllItemsEntry) -> Bool {
        switch sort {
        case .alphabetical:
            return alphaKey(for: lhs.event) < alphaKey(for: rhs.event)
        case .soonest:
            return compareSoonest(lhs, rhs)
        }
    }

    private func compareSoonest(_ lhs: AllItemsEntry, _ rhs: AllItemsEntry) -> Bool {
        switch (lhs.nextOccurrence, rhs.nextOccurrence) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        switch (lhs.fallbackOccurrence, rhs.fallbackOccurrence) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        return alphaKey(for: lhs.event) < alphaKey(for: rhs.event)
    }

    private func alphaKey(for event: CustomEvent) -> String {
        event.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func openEditor(for event: CustomEvent) {
        if event.isReminder {
            editingReminder = event
        } else {
            editingEvent = event
        }
    }

    private func preferredDate(for event: CustomEvent) -> Date {
        nextUpcomingOccurrence(for: event, from: Date())
        ?? fallbackDisplayDate(for: event)
        ?? Date()
    }

    private func fallbackDisplayDate(for event: CustomEvent) -> Date? {
        if let firstDate = event.firstApplicableDate {
            return combinedDate(day: firstDate, time: event.startTime)
        }
        return nil
    }

    private func nextUpcomingOccurrence(for event: CustomEvent, from referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)

        switch event.repeatPattern {
        case .none:
            guard let firstDate = event.firstApplicableDate else { return nil }
            let occurrence = combinedDate(day: firstDate, time: event.startTime)
            return occurrence >= referenceDate ? occurrence : nil

        case .daily:
            return nextScheduleDate(
                after: referenceDate,
                matching: { _, entry in
                    guard let dayCode = entry.first else { return false }
                    return !dayCode.isEmpty && dayCode != "None"
                },
                fallbackTo: startOfReferenceDay,
                time: event.startTime
            )

        case .weekly, .biweekly:
            return nextScheduleDate(
                after: referenceDate,
                matching: { _, entry in
                    guard let dayCode = entry.first else { return false }
                    return event.applicableDays.contains(dayCode)
                },
                fallbackTo: startOfReferenceDay,
                time: event.startTime
            )

        case .weekday:
            let selectedWeekdays = Set(event.applicableDays.compactMap(Int.init))
            guard !selectedWeekdays.isEmpty else { return nil }

            for offset in 0...365 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: startOfReferenceDay) else { continue }
                let weekday = calendar.component(.weekday, from: candidate)
                guard selectedWeekdays.contains(weekday) else { continue }
                let occurrence = combinedDate(day: candidate, time: event.startTime)
                if occurrence >= referenceDate {
                    return occurrence
                }
            }
            return nil

        case .monthly:
            let dayOfMonth = calendar.component(.day, from: event.firstApplicableDate ?? referenceDate)
            let baseMonth = calendar.dateComponents([.year, .month], from: startOfReferenceDay)

            for monthOffset in 0...24 {
                guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: calendar.date(from: baseMonth) ?? startOfReferenceDay) else { continue }
                var components = calendar.dateComponents([.year, .month], from: monthStart)
                components.day = dayOfMonth
                guard let candidate = calendar.date(from: components) else { continue }
                let candidateDay = calendar.component(.day, from: candidate)
                guard candidateDay == dayOfMonth else { continue }
                let occurrence = combinedDate(day: candidate, time: event.startTime)
                if occurrence >= referenceDate {
                    return occurrence
                }
            }
            return nil
        }
    }

    private func nextScheduleDate(
        after referenceDate: Date,
        matching matcher: (String, [String]) -> Bool,
        fallbackTo fallbackDate: Date,
        time: Time
    ) -> Date? {
        guard let scheduleDict else { return nil }

        let candidates = scheduleDict.compactMap { key, value -> Date? in
            guard matcher(key, value), let day = scheduleDate(from: key) else { return nil }
            return combinedDate(day: day, time: time)
        }
        .sorted()

        return candidates.first(where: { $0 >= referenceDate })
            ?? candidates.first(where: { $0 >= fallbackDate })
    }

    private func scheduleDate(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        return formatter.date(from: key)
    }

    private func combinedDate(day: Date, time: Time) -> Date {
        time.toDate(on: day)
    }
}
