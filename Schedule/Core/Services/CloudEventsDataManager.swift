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

class CloudEventsDataManager {
    private let firestore  = Firestore.firestore()
    private let encryption = EncryptionService.shared

    // -------------------------------------------------------------------------
    // MARK: Save
    // -------------------------------------------------------------------------

    func saveEvents(_ events: [CustomEvent], for userId: String) async throws {
        let encryptedBlob = try encryption.encrypt(events, userId: userId)

        try await firestore.collection("users").document(userId).setData([
            "eventsEncrypted":    true,         // ← migration flag
            "customEvents":       encryptedBlob,
            "eventsLastUpdated":  FieldValue.serverTimestamp()
        ], merge: true)
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
            return (try? encryption.decrypt(blob, as: [CustomEvent].self, userId: userId)) ?? []
        }

        // ── Legacy plaintext path ────────────────────────────────────────────
        guard let eventsArray = data["customEvents"] as? [[String: Any]] else { return [] }
        return eventsArray.compactMap { Self.eventFromDict($0) }
    }

    // -------------------------------------------------------------------------
    // MARK: Private — legacy decoder (unchanged from original)
    // -------------------------------------------------------------------------

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

        return CustomEvent(
            id:              id,
            title:           title,
            startTime:       startTime,
            endTime:         endTime,
            location:        location,
            note:            note,
            color:           color,
            repeatPattern:   repeatPattern,
            applicableDays:  Set(applicableDaysArr)
        )
    }
}
