//
//  CustomEventsManager.swift
//  Schedule
//
//  Fix 4: Deletion race condition eliminated by removing the concurrent
//  dispatch queue entirely. All mutations now happen directly on the
//  MainActor, which is already where callers (SwiftUI gestures,
//  @MainActor ViewModels) live. The barrier queue was creating a
//  write/saveEvents() race because @Published writes must happen on
//  the main thread while the barrier fired on a background thread.
//

import Foundation
import SwiftUI
import FirebaseFirestore

@MainActor
class CustomEventsManager: ObservableObject {
    @Published var events: [CustomEvent] = []

    private let userDefaults = UserDefaults.standard
    private let eventsKey    = "CustomEvents"
    private var authManager: AuthenticationManager?
    private var isPurgingExpiredReminders = false

    init() {
        loadEvents()
    }

    func setAuthManager(_ manager: AuthenticationManager) {
        authManager = manager
    }

    // MARK: - Persistence

    func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            userDefaults.set(data, forKey: eventsKey)
            SharedGroup.defaults.set(data, forKey: "CustomEvents")
            NotificationManager.shared.scheduleReminderNotifications(for: events)

            if authManager?.user != nil {
                Task { await saveToCloudAsync() }
            }
        } catch {
            print("❌ Failed to save custom events: \(error)")
        }
    }

    func loadEvents() {
        guard let data = userDefaults.data(forKey: eventsKey) else { return }
        do {
            events = try JSONDecoder().decode([CustomEvent].self, from: data)
            purgeExpiredReminders()
            NotificationManager.shared.scheduleReminderNotifications(for: events)
        } catch {
            print("❌ Failed to load custom events: \(error)")
        }
    }

    // MARK: - Cloud Sync

    func saveToCloud(using authManager: AuthenticationManager) {
        guard let user = authManager.user else { return }
        let userId       = user.id
        let eventsToSave = events
        Task {
            do {
                try await CloudEventsDataManager().saveEvents(eventsToSave, for: userId)
            } catch {
                print("❌ Failed to save events to cloud: \(error)")
            }
        }
    }

    func loadFromCloud(using authManager: AuthenticationManager) {
        guard let user = authManager.user else { return }
        let userId = user.id
        Task {
            do {
                let cloudEvents = try await CloudEventsDataManager().loadEvents(for: userId)
                if !cloudEvents.isEmpty {
                    events = cloudEvents
                    purgeExpiredReminders()
                    saveEvents()
                } else {
                    NotificationManager.shared.scheduleReminderNotifications(for: events)
                }
            } catch {
                print("❌ Failed to load events from cloud: \(error)")
            }
        }
    }

    private func saveToCloudAsync() async {
        guard let user = authManager?.user else { return }
        do {
            try await CloudEventsDataManager().saveEvents(events, for: user.id)
        } catch {
            print("❌ Failed to auto-save events to cloud: \(error)")
        }
    }

    // MARK: - Event Management (all on MainActor — no queue needed)

    /// Adds a new event. Identical to addEventSync; kept for call-site compat.
    func addEvent(_ event: CustomEvent) {
        events.append(event)
        saveEvents()
    }

    /// Updates an existing event in-place.
    func updateEvent(_ event: CustomEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[index] = event
        saveEvents()
    }

    /// Removes an event. Fix 4: now atomic — no barrier/main-thread split.
    func deleteEvent(_ event: CustomEvent) {
        events.removeAll { $0.id == event.id }
        saveEvents()
    }

    // These remain for call sites that use the "Sync" suffix
    func addEventSync(_ event: CustomEvent)    { addEvent(event) }
    func updateEventSync(_ event: CustomEvent) { updateEvent(event) }

    // MARK: - Event Filtering

    func eventsFor(dayCode: String, date: Date) -> [CustomEvent] {
        purgeExpiredReminders()
        return events.filter { $0.appliesTo(dayCode: dayCode, date: date) }
    }

    func purgeExpiredReminders(referenceDate: Date = Date()) {
        guard !isPurgingExpiredReminders else { return }

        let filteredEvents = events.filter { event in
            guard event.isReminder,
                  let reminderEndDate = event.reminderEndDate else {
                return true
            }
            return reminderEndDate > referenceDate
        }

        guard filteredEvents.count != events.count else { return }

        isPurgingExpiredReminders = true
        events = filteredEvents
        saveEvents()
        isPurgingExpiredReminders = false
    }

    // MARK: - Conflict Detection

    func detectConflicts(for event: CustomEvent, with scheduleLines: [ScheduleLine]) -> [EventConflict] {
        scheduleLines.compactMap { line in
            guard event.conflictsWith(line) else { return nil }
            return EventConflict(
                event: event,
                conflictingScheduleLine: line,
                severity: calculateConflictSeverity(event: event, scheduleLine: line)
            )
        }
    }

    private func calculateConflictSeverity(event: CustomEvent, scheduleLine: ScheduleLine) -> ConflictSeverity {
        guard let classStart = scheduleLine.startSec,
              let classEnd   = scheduleLine.endSec else { return .minor }

        let eventStart   = event.startTime.seconds
        let eventEnd     = event.endTime.seconds
        let overlapStart = max(eventStart, classStart)
        let overlapEnd   = min(eventEnd, classEnd)
        let overlap      = overlapEnd - overlapStart

        if overlap >= (classEnd - classStart) * 8 / 10 { return .complete }
        if overlap >= 900                               { return .major    }
        return .minor
    }
}
