//
//  CustomEventsManager.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation
import SwiftUI

class CustomEventsManager: ObservableObject {
    @Published var events: [CustomEvent] = []
    
    private let userDefaults = UserDefaults.standard
    private let eventsKey = "CustomEvents"
    
    init() {
        loadEvents()
    }
    
    // MARK: - Persistence
    
    func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            userDefaults.set(data, forKey: eventsKey)
            SharedGroup.defaults.set(data, forKey: "CustomEvents")
        } catch {
            print("❌ Failed to save custom events: \(error)")
        }
    }
    
    func loadEvents() {
        guard let data = userDefaults.data(forKey: eventsKey) else { return }
        do {
            events = try JSONDecoder().decode([CustomEvent].self, from: data)
        } catch {
            print("❌ Failed to load custom events: \(error)")
        }
    }
    
    // MARK: - Cloud Sync
    
    @MainActor
    func saveToCloud(using authManager: AuthenticationManager) {
        guard let user = authManager.user else { return }
        let userId = user.id
        let eventsToSave = events
        
        Task {
            do {
                try await CloudEventsDataManager().saveEvents(eventsToSave, for: userId)
            } catch {
                print("❌ Failed to save events to cloud: \(error)")
            }
        }
    }
    
    @MainActor
    func loadFromCloud(using authManager: AuthenticationManager) {
        guard let user = authManager.user else { return }
        let userId = user.id
        
        Task {
            do {
                let cloudEvents = try await CloudEventsDataManager().loadEvents(for: userId)
                await MainActor.run {
                    if !cloudEvents.isEmpty {
                        self.events = cloudEvents
                        self.saveEvents()
                    }
                }
            } catch {
                print("❌ Failed to load events from cloud: \(error)")
            }
        }
    }
    
    // MARK: - Event Management
    
    func addEvent(_ event: CustomEvent) {
        events.append(event)
        saveEvents()
    }
    
    func updateEvent(_ event: CustomEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            saveEvents()
        }
    }
    
    func deleteEvent(_ event: CustomEvent) {
        events.removeAll { $0.id == event.id }
        saveEvents()
    }
    
    func toggleEvent(_ event: CustomEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index].isEnabled.toggle()
            saveEvents()
        }
    }
    
    // MARK: - Event Filtering
    
    func eventsFor(dayCode: String, date: Date) -> [CustomEvent] {
        return events.filter { $0.appliesTo(dayCode: dayCode, date: date) }
    }
    
    // MARK: - Conflict Detection
    
    func detectConflicts(for event: CustomEvent, with scheduleLines: [ScheduleLine]) -> [EventConflict] {
        var conflicts: [EventConflict] = []
        
        for line in scheduleLines {
            if event.conflictsWith(line) {
                let severity = calculateConflictSeverity(event: event, scheduleLine: line)
                conflicts.append(EventConflict(event: event, conflictingScheduleLine: line, severity: severity))
            }
        }
        
        return conflicts
    }
    
    private func calculateConflictSeverity(event: CustomEvent, scheduleLine: ScheduleLine) -> ConflictSeverity {
        guard let classStart = scheduleLine.startSec,
              let classEnd = scheduleLine.endSec else { return .minor }
        
        let eventStart = event.startTime.seconds
        let eventEnd = event.endTime.seconds
        
        let overlapStart = max(eventStart, classStart)
        let overlapEnd = min(eventEnd, classEnd)
        let overlapDuration = overlapEnd - overlapStart
        
        if overlapDuration >= (classEnd - classStart) * 8 / 10 {
            return .complete
        } else if overlapDuration >= 900 {
            return .major
        } else {
            return .minor
        }
    }
}
