//
//  CloudEventsDataManager.swift
//  Schedule
//
//  Created by Andreas Royset on 3/17/26.
//
//
//  Drop-in replacement for the CloudEventsDataManager class inside
//  CustomEventsManager.swift.  Encrypts the entire events array as a
//  single JSON blob before writing to Firestore and decrypts on load.
//  Old documents without the "eventsEncrypted" flag are loaded as
//  plaintext and upgraded automatically on the next save.
//

import FirebaseFirestore

@MainActor
final class CloudEventsDataManager {
    static let shared = CloudEventsDataManager()

    private let firestore  = Firestore.firestore()
    private let encryption = EncryptionService.shared

    private struct CloudSnapshot {
        let events: [CustomEvent]
        let isEncrypted: Bool
    }

    private struct PendingSave {
        let id: UUID
        let task: Task<Void, Error>
    }

    private static var snapshots: [String: CloudSnapshot] = [:]
    private static var usersNeedingRewrite: Set<String> = []
    private static var pendingSaves: [String: PendingSave] = [:]

    // -------------------------------------------------------------------------
    // MARK: Save
    // -------------------------------------------------------------------------

    func saveEvents(_ events: [CustomEvent], for userId: String) async throws {
        let previousTask = Self.pendingSaves[userId]?.task
        let saveID = UUID()
        let task = Task { @MainActor [self] in
            if let previousTask {
                _ = try? await previousTask.value
            }
            try await writeEventsIfChanged(events, for: userId)
        }

        Self.pendingSaves[userId] = PendingSave(id: saveID, task: task)

        do {
            try await task.value
            clearPendingSave(saveID, for: userId)
        } catch {
            clearPendingSave(saveID, for: userId)
            throw error
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Load  (encrypted + legacy plaintext)
    // -------------------------------------------------------------------------

    func loadEvents(for userId: String) async throws -> [CustomEvent] {
        let doc = try await firestore.collection("users").document(userId).getDocument()
        guard let data = doc.data() else { return [] }

        // ── Encrypted path ───────────────────────────────────────────────────
        if data["eventsEncrypted"] as? Bool == true,
           let blob = data["customEvents"] as? String {
            let events = (try? encryption.decrypt(blob, as: [CustomEvent].self, userId: userId)) ?? []
            Self.snapshots[userId] = CloudSnapshot(events: events, isEncrypted: true)
            return events
        }

        // ── Legacy plaintext path ────────────────────────────────────────────
        guard let eventsArray = data["customEvents"] as? [[String: Any]] else {
            Self.snapshots[userId] = CloudSnapshot(events: [], isEncrypted: false)
            return []
        }
        let events = eventsArray.compactMap { Self.eventFromDict($0) }
        Self.snapshots[userId] = CloudSnapshot(events: events, isEncrypted: false)
        Self.usersNeedingRewrite.insert(userId)
        return events
    }

    // -------------------------------------------------------------------------
    // MARK: Private — legacy decoder (unchanged from original)
    // -------------------------------------------------------------------------

    private func writeEventsIfChanged(_ events: [CustomEvent], for userId: String) async throws {
        let previous = Self.snapshots[userId]
        let needsRewrite = Self.usersNeedingRewrite.contains(userId)
        guard previous?.events != events || previous?.isEncrypted != true || needsRewrite else {
            return
        }

        var changedData: [String: Any] = [
            "customEvents": try encryption.encrypt(events, userId: userId),
            "eventsLastUpdated": FieldValue.serverTimestamp()
        ]
        if previous?.isEncrypted != true {
            changedData["eventsEncrypted"] = true
        }

        try await firestore.collection("users").document(userId).setData(changedData, merge: true)
        Self.snapshots[userId] = CloudSnapshot(events: events, isEncrypted: true)
        Self.usersNeedingRewrite.remove(userId)
    }

    private func clearPendingSave(_ saveID: UUID, for userId: String) {
        guard Self.pendingSaves[userId]?.id == saveID else { return }
        Self.pendingSaves[userId] = nil
    }

    private static func eventFromDict(_ eventDict: [String: Any]) -> CustomEvent? {
        guard
            let idString           = eventDict["id"]            as? String,
            let id                 = UUID(uuidString: idString),
            let title              = eventDict["title"]         as? String,
            let startTimeDict      = eventDict["startTime"]     as? [String: Int],
            let endTimeDict        = eventDict["endTime"]       as? [String: Int],
            let location           = eventDict["location"]      as? String,
            let note               = eventDict["note"]          as? String,
            let color              = eventDict["color"]         as? String,
            let repeatPatternRaw   = eventDict["repeatPattern"] as? String,
            let repeatPattern      = RepeatPattern(rawValue: repeatPatternRaw),
            let applicableDaysArr  = eventDict["applicableDays"] as? [String]
        else { return nil }

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
        let kindRaw = eventDict["kind"] as? String
        let kind = CustomItemKind(rawValue: kindRaw ?? "") ?? .event
        let reminderOffsetsRaw = eventDict["reminderOffsets"] as? [String] ?? []
        let reminderOffsets = reminderOffsetsRaw.compactMap(ReminderOffset.init(rawValue:))

        return CustomEvent(
            id:              id,
            title:           title,
            startTime:       startTime,
            endTime:         endTime,
            location:        location,
            note:            note,
            color:           color,
            repeatPattern:   repeatPattern,
            kind:            kind,
            reminderOffsets: reminderOffsets,
            applicableDays:  Set(applicableDaysArr)
        )
    }
}
