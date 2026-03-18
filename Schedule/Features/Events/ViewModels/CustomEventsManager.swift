//
//  CustomEventsManager.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation
import SwiftUI
import FirebaseFirestore

class CustomEventsManager: ObservableObject {
    @Published var events: [CustomEvent] = []
    
    private let userDefaults = UserDefaults.standard
    private let eventsKey = "CustomEvents"
    private let syncQueue = DispatchQueue(label: "com.schedule.events.sync", attributes: .concurrent)
    private var authManager: AuthenticationManager?
    
    init() {
        loadEvents()
    }
    
    func setAuthManager(_ manager: AuthenticationManager) {
        self.authManager = manager
    }
    
    // MARK: - Persistence
    
    @MainActor func saveEvents() {
        let hasUser = authManager?.user != nil
        
        do {
            let data = try JSONEncoder().encode(self.events)
            self.userDefaults.set(data, forKey: self.eventsKey)
            SharedGroup.defaults.set(data, forKey: "CustomEvents")
            
            if hasUser {
                Task {
                    await self.saveToCloudAsync()
                }
            }
        } catch {
            print("❌ Failed to save custom events: \(error)")
        }
    }
    
    func loadEvents() {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = self.userDefaults.data(forKey: self.eventsKey) else { return }
            do {
                let loadedEvents = try JSONDecoder().decode([CustomEvent].self, from: data)
                DispatchQueue.main.async {
                    self.events = loadedEvents
                }
            } catch {
                print("❌ Failed to load custom events: \(error)")
            }
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
    
    private func saveToCloudAsync() async {
        guard let authManager = authManager,
              let user = await authManager.user else { return }
        
        do {
            try await CloudEventsDataManager().saveEvents(events, for: user.id)
        } catch {
            print("❌ Failed to auto-save events to cloud: \(error)")
        }
    }
    
    // MARK: - Event Management
    
    func addEvent(_ event: CustomEvent) {
        syncQueue.async(flags: .barrier) { [weak self] in
            self?.events.append(event)
            DispatchQueue.main.async {
                self?.saveEvents()
            }
        }
    }

    func updateEvent(_ event: CustomEvent) {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let index = self.events.firstIndex(where: { $0.id == event.id }) {
                self.events[index] = event
                DispatchQueue.main.async {
                    self.saveEvents()
                }
            }
        }
    }

    func deleteEvent(_ event: CustomEvent) {
        syncQueue.async(flags: .barrier) { [weak self] in
            self?.events.removeAll { $0.id == event.id }
            DispatchQueue.main.async {
                self?.saveEvents()
            }
        }
    }
    
    // MARK: - Event Filtering
    
    func eventsFor(dayCode: String, date: Date) -> [CustomEvent] {
        return syncQueue.sync {
            return events.filter { $0.appliesTo(dayCode: dayCode, date: date) }
        }
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
    
    @MainActor
    func updateEventSync(_ event: CustomEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        }
        saveEvents()
    }
 
    @MainActor
    func addEventSync(_ event: CustomEvent) {
        events.append(event)
        saveEvents()
    }
}
