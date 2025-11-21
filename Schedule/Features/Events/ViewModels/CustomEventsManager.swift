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
    private var authManager: AuthenticationManager?
    
    init() {
        loadEvents()
    }
    
    func setAuthManager(_ manager: AuthenticationManager) {
            self.authManager = manager
        }
    
    // MARK: - Persistence
    
    @MainActor func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            userDefaults.set(data, forKey: eventsKey)
            SharedGroup.defaults.set(data, forKey: "CustomEvents")
            
            if authManager?.user != nil {
                Task {
                    await saveToCloudAsync()
                }
            }
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
    
    private func saveToCloudAsync() async {
        guard let authManager = authManager,
              let user = await authManager.user else { return }
        
        do {
            try await CloudEventsDataManager().saveEvents(events, for: user.id)
            print("✅ Events auto-saved to cloud")
        } catch {
            print("❌ Failed to auto-save events to cloud: \(error)")
        }
    }
    
    // MARK: - Event Management
    
    @MainActor func addEvent(_ event: CustomEvent) {
        events.append(event)
        saveEvents()
    }
    
    @MainActor func updateEvent(_ event: CustomEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            saveEvents()
        }
    }
    
    @MainActor func deleteEvent(_ event: CustomEvent) {
        events.removeAll { $0.id == event.id }
        saveEvents()
    }
    
    @MainActor func toggleEvent(_ event: CustomEvent) {
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

class CloudEventsDataManager {
    private let firestore = Firestore.firestore()
    
    func saveEvents(_ events: [CustomEvent], for userId: String) async throws {
        let eventsData = events.map { event in
            [
                "id": event.id.uuidString,
                "title": event.title,
                "startTime": [
                    "h": event.startTime.h,
                    "m": event.startTime.m,
                    "s": event.startTime.s
                ],
                "endTime": [
                    "h": event.endTime.h,
                    "m": event.endTime.m,
                    "s": event.endTime.s
                ],
                "location": event.location,
                "note": event.note,
                "color": event.color,
                "repeatPattern": event.repeatPattern.rawValue,
                "isEnabled": event.isEnabled,
                "applicableDays": Array(event.applicableDays)
            ] as [String : Any]
        }
        
        try await firestore.collection("users").document(userId).setData([
            "customEvents": eventsData,
            "eventsLastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func loadEvents(for userId: String) async throws -> [CustomEvent] {
        let doc = try await firestore.collection("users").document(userId).getDocument()
        guard let data = doc.data(),
              let eventsArray = data["customEvents"] as? [[String: Any]] else {
            return []
        }
        
        return eventsArray.compactMap { eventDict in
            guard let idString = eventDict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = eventDict["title"] as? String,
                  let startTimeDict = eventDict["startTime"] as? [String: Int],
                  let endTimeDict = eventDict["endTime"] as? [String: Int],
                  let location = eventDict["location"] as? String,
                  let note = eventDict["note"] as? String,
                  let color = eventDict["color"] as? String,
                  let repeatPatternRaw = eventDict["repeatPattern"] as? String,
                  let repeatPattern = RepeatPattern(rawValue: repeatPatternRaw),
                  let isEnabled = eventDict["isEnabled"] as? Bool,
                  let applicableDaysArray = eventDict["applicableDays"] as? [String] else {
                return nil
            }
            
            let startTime = Time(
                h: startTimeDict["h"] ?? 0,
                m: startTimeDict["m"] ?? 0,
                s: startTimeDict["s"] ?? 0
            )
            
            let endTime = Time(
                h: endTimeDict["h"] ?? 0,
                m: endTimeDict["m"] ?? 0,
                s: endTimeDict["s"] ?? 0
            )
            
            return CustomEvent(
                id: id,
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location,
                note: note,
                color: color,
                repeatPattern: repeatPattern,
                applicableDays: Set(applicableDaysArray),
                isEnabled: isEnabled
            )
        }
    }
}
