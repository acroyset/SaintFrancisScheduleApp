//
//  CloudEventsDataManager.swift
//  Schedule
//
//  Created by Andreas Royset on 3/17/26.
//
//
//  Encrypts the entire event array. Schema 5 uses the non-colliding
//  `cloudDataV5` map while continuing to mirror the released top-level event
//  fields so older devices remain usable during rollout.
//

import FirebaseFirestore

struct PersistedEventsState: Equatable {
    let events: [CustomEvent]
    /// False means the user document or event domain does not exist. An
    /// authoritative state may still contain an intentionally empty array.
    let isAuthoritative: Bool
}

@MainActor
protocol EventsCloudSyncing: AnyObject {
    func saveEvents(_ events: [CustomEvent], for userId: String) async throws
    func loadEvents(for userId: String) async throws -> [CustomEvent]
    func loadEventState(for userId: String) async throws -> PersistedEventsState
    func observeEvents(
        for userId: String,
        onChange: @escaping @MainActor (Result<[CustomEvent], Error>) -> Void
    ) -> CloudSyncObservation?
}

extension EventsCloudSyncing {
    func loadEventState(for userId: String) async throws -> PersistedEventsState {
        PersistedEventsState(
            events: try await loadEvents(for: userId),
            isAuthoritative: true
        )
    }

    func observeEvents(
        for userId: String,
        onChange: @escaping @MainActor (Result<[CustomEvent], Error>) -> Void
    ) -> CloudSyncObservation? {
        nil
    }
}

@MainActor
final class CloudEventsDataManager: EventsCloudSyncing {
    static let shared = CloudEventsDataManager()

    // The view model is also created by previews and deterministic UI tests,
    // where Firebase is intentionally not configured. Resolve Firestore only
    // when a real cloud operation begins, after production startup completes.
    private lazy var firestore = Firestore.firestore()
    private let encryption = EncryptionService.shared
    nonisolated private static let schemaVersion = 5

    private struct CloudSnapshot {
        let events: [CustomEvent]
        let isEncrypted: Bool
        let isCanonical: Bool
    }

    private struct PendingSave {
        let id: UUID
        let task: Task<Void, Error>
    }

    private final class ListenerState {
        var latestTimestamp: Date = .distantPast
        var hasDeliveredValue = false
        var latestEvents: [CustomEvent]?
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
            try DataManager.assertCloudWriteAllowed(for: userId)
            let hadTrustedBaseline = Self.snapshots[userId] != nil
            if !hadTrustedBaseline {
                try await loadEventBaselineWhenAvailable(for: userId)
            }
            try await writeEventsIfChanged(
                events,
                mayRestoreTombstones: hadTrustedBaseline,
                for: userId
            )
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

    private func loadEventBaselineWhenAvailable(for userId: String) async throws {
        while true {
            do {
                _ = try await loadEventState(for: userId)
                return
            } catch where DataManager.isFirestoreUnavailable(error) {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Load  (encrypted + legacy plaintext)
    // -------------------------------------------------------------------------

    func loadEvents(for userId: String) async throws -> [CustomEvent] {
        try await loadEventState(for: userId).events
    }

    func loadEventState(for userId: String) async throws -> PersistedEventsState {
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: userId)
        let data: [String: Any]
        if let cached = DataManager.recentValidatedRootData(for: userId) {
            data = cached
        } else {
            data = try await userDocument(for: userId).getDocument().data() ?? [:]
            DataManager.cacheValidatedRoot(data, for: userId)
        }
        if let cloudData = try Self.version5CloudData(in: data) {
            let version = (cloudData["schemaVersion"] as? NSNumber)?.intValue ?? 0
            if version > Self.schemaVersion {
                throw CloudDataSchemaError.unsupportedVersion(version)
            }
            guard version == Self.schemaVersion,
                  let blob = cloudData["events"] as? String else {
                throw CloudDataSchemaError.corruptPayload("events")
            }
            let events: [CustomEvent]
            do {
                events = try encryption.decrypt(
                    blob,
                    as: [CustomEvent].self,
                    userId: userId
                ).filter { !Self.eventTombstones(in: cloudData).contains($0.id.uuidString) }
            } catch {
                DataManager.noteCloudReadFailure(error, for: userId)
                throw error
            }
            Self.snapshots[userId] = CloudSnapshot(
                events: events,
                isEncrypted: true,
                isCanonical: true
            )
            return PersistedEventsState(
                events: events,
                // The flag was added after schema 5 shipped internally, so a
                // missing value remains authoritative for compatibility.
                isAuthoritative: cloudData["eventsInitialized"] as? Bool != false
            )
        }

        guard !data.isEmpty else {
            Self.snapshots[userId] = nil
            Self.usersNeedingRewrite.remove(userId)
            return PersistedEventsState(events: [], isAuthoritative: false)
        }

        // ── Encrypted path ───────────────────────────────────────────────────
        if data["eventsEncrypted"] as? Bool == true {
            guard let blob = data["customEvents"] as? String else {
                throw EncryptionError.invalidData
            }
            let events = try encryption.decrypt(blob, as: [CustomEvent].self, userId: userId)
            Self.snapshots[userId] = CloudSnapshot(
                events: events,
                isEncrypted: true,
                isCanonical: false
            )
            return PersistedEventsState(events: events, isAuthoritative: true)
        }

        // ── Legacy plaintext path ────────────────────────────────────────────
        guard let storedEvents = data["customEvents"] else {
            Self.snapshots[userId] = CloudSnapshot(
                events: [],
                isEncrypted: false,
                isCanonical: false
            )
            return PersistedEventsState(events: [], isAuthoritative: false)
        }
        guard let eventsArray = storedEvents as? [[String: Any]] else {
            throw EncryptionError.invalidData
        }
        let events = eventsArray.compactMap { Self.eventFromDict($0) }
        guard events.count == eventsArray.count else { throw EncryptionError.invalidData }
        Self.snapshots[userId] = CloudSnapshot(
            events: events,
            isEncrypted: false,
            isCanonical: false
        )
        Self.usersNeedingRewrite.insert(userId)
        return PersistedEventsState(events: events, isAuthoritative: true)
    }

    func observeEvents(
        for userId: String,
        onChange: @escaping @MainActor (Result<[CustomEvent], Error>) -> Void
    ) -> CloudSyncObservation? {
        let state = ListenerState()
        let deliver: @MainActor ([CustomEvent], Date) -> Void = { events, timestamp in
            // The root document listener is ordered, but imported payload
            // timestamps are not trustworthy ordering tokens. A single clock
            // set years ahead must not hide every later server-timestamped edit.
            guard state.latestEvents != events else { return }
            state.hasDeliveredValue = true
            state.latestTimestamp = max(state.latestTimestamp, timestamp)
            state.latestEvents = events
            Self.snapshots[userId] = CloudSnapshot(
                events: events,
                isEncrypted: true,
                isCanonical: true
            )
            onChange(.success(events))
        }

        let canonicalListener = userDocument(for: userId).addSnapshotListener(
            includeMetadataChanges: true
        ) { [encryption] snapshot, error in
            Task { @MainActor in
                if let error { onChange(.failure(error)); return }
                guard let snapshot else { return }
                if !snapshot.exists {
                    // Do not treat an offline cache miss as a remote delete.
                    // A server-confirmed missing shared root is not an event
                    // deletion either: account deletion signs the user out,
                    // while a transient/operational root loss must not erase
                    // every event on established devices. Reset ordering and
                    // caches so an older restored backup can be accepted, then
                    // wait for an actual root payload.
                    guard !snapshot.metadata.isFromCache else { return }
                    state.hasDeliveredValue = false
                    state.latestTimestamp = .distantPast
                    state.latestEvents = nil
                    _ = Self.eventsForMissingRoot(for: userId)
                    return
                }
                guard let data = snapshot.data() else { return }
                guard !snapshot.metadata.hasPendingWrites else { return }
                do {
                    DataManager.cacheValidatedRoot(data, for: userId)
                    guard let cloudData = try Self.version5CloudData(in: data) else { return }
                    let version = (cloudData["schemaVersion"] as? NSNumber)?.intValue ?? 0
                    if version > Self.schemaVersion {
                        throw CloudDataSchemaError.unsupportedVersion(version)
                    }
                    guard version == Self.schemaVersion,
                          let blob = cloudData["events"] as? String else {
                        throw CloudDataSchemaError.corruptPayload("events")
                    }
                    if cloudData["eventsInitialized"] as? Bool == false {
                        // Migration synthesized an empty event payload while
                        // recovering a schedule-only root. It is not a remote
                        // instruction to erase established device events.
                        state.hasDeliveredValue = false
                        state.latestTimestamp = .distantPast
                        state.latestEvents = nil
                        _ = Self.eventsForMissingRoot(for: userId)
                        // A released client may later repopulate the top-level
                        // event mirror. Re-run arbitration so that real source
                        // can establish authority instead of leaving this
                        // listener permanently parked on the synthesized state.
                        Task { @MainActor in
                            try? await DataManager().migrateLegacyUserDocumentIfNeeded(for: userId)
                        }
                        return
                    }
                    let tombstones = Self.eventTombstones(in: cloudData)
                    let tombstoneBases = DataManager.eventTombstoneBases(in: cloudData)
                    let canonicalEvents = try encryption.decrypt(
                        blob,
                        as: [CustomEvent].self,
                        userId: userId
                    ).filter { !tombstones.contains($0.id.uuidString) }
                    let canonicalTimestamp = (cloudData["eventsUpdatedAt"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                    let eventsTimestamp = (data["eventsUpdatedAt"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                    let releasedEventsTimestamp = (data["eventsLastUpdated"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                    let rootTimestamp = (data["lastUpdated"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                    let domainTimestamp = max(releasedEventsTimestamp, eventsTimestamp)
                    let legacyTimestamp = domainTimestamp == .distantPast
                        ? rootTimestamp
                        : domainTimestamp
                    if let legacyEvents = try Self.decodeLegacyEvents(
                        in: data,
                        encryption: encryption,
                        userId: userId
                    ) {
                        let resolved = DataManager.resolvingEventTombstones(
                            legacyEvents,
                            tombstones: tombstones,
                            bases: tombstoneBases
                        )
                        var resolvedTombstones = tombstones
                        resolvedTombstones.subtract(resolved.restoredIDs)
                        let sanitizedLegacyEvents = resolved.value.filter {
                            !resolvedTombstones.contains($0.id.uuidString)
                        }
                        let valuesDiffer = sanitizedLegacyEvents != canonicalEvents
                        if valuesDiffer,
                           !DataManager.eventValuesDifferOnlyByVerifiedRestorations(
                               sanitizedLegacyEvents,
                               canonicalEvents,
                               restoredIDs: resolved.restoredIDs
                           ),
                           DataManager.importedTimestampOrderingIsAmbiguous(
                               legacyTimestamp,
                               canonicalTimestamp
                           ) {
                            throw CloudDataSchemaError.corruptPayload(
                                "ambiguous future events timestamp"
                            )
                        }
                        if legacyTimestamp > canonicalTimestamp, valuesDiffer {
                            deliver(sanitizedLegacyEvents, legacyTimestamp)
                            Task { @MainActor in
                                try? await DataManager().migrateLegacyUserDocumentIfNeeded(
                                    for: userId
                                )
                            }
                        } else {
                            deliver(canonicalEvents, canonicalTimestamp)
                        }
                    } else {
                        deliver(canonicalEvents, canonicalTimestamp)
                    }
                } catch {
                    DataManager.noteCloudReadFailure(error, for: userId)
                    onChange(.failure(error))
                }
            }
        }
        return CloudSyncObservation {
            canonicalListener.remove()
        }
    }

    /// Clears event-domain caches when the shared user root is deleted. The
    /// empty value is an explicit listener update rather than a cached value.
    static func eventsForMissingRoot(for userId: String) -> [CustomEvent] {
        snapshots[userId] = nil
        usersNeedingRewrite.remove(userId)
        DataManager.clearValidatedRootCache(for: userId)
        return []
    }

    // -------------------------------------------------------------------------
    // MARK: Private — legacy decoder (unchanged from original)
    // -------------------------------------------------------------------------

    private func writeEventsIfChanged(
        _ events: [CustomEvent],
        mayRestoreTombstones: Bool,
        for userId: String
    ) async throws {
        let previous = Self.snapshots[userId]
        let needsRewrite = Self.usersNeedingRewrite.contains(userId)
        guard previous?.events != events
                || previous?.isEncrypted != true
                || previous?.isCanonical != true
                || needsRewrite else {
            return
        }

        let base = previous?.events ?? []
        let baseIDs = Set(base.map { $0.id.uuidString })
        let localIDs = Set(events.map { $0.id.uuidString })
        let locallyDeletedIDs = baseIDs.subtracting(localIDs)
        let explicitlyRestoredIDs = localIDs.subtracting(baseIDs)
        let baseByID = Dictionary(
            base.map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let locallyEditedIDs = Set(events.compactMap { event -> String? in
            let id = event.id.uuidString
            guard let baseEvent = baseByID[id], baseEvent != event else { return nil }
            return id
        })
        let reference = userDocument(for: userId)
        let result = try await firestore.runTransaction { [encryption] transaction, errorPointer in
            do {
                let root = try transaction.getDocument(reference).data() ?? [:]
                if let transitional = root["cloudData"] as? [String: Any] {
                    let version = (transitional["schemaVersion"] as? NSNumber)?.intValue ?? 0
                    if version > Self.schemaVersion {
                        throw CloudDataSchemaError.unsupportedVersion(version)
                    }
                }

                var cloud = try Self.version5CloudData(in: root) ?? [:]
                let storedVersion = (cloud["schemaVersion"] as? NSNumber)?.intValue ?? 0
                if storedVersion > Self.schemaVersion {
                    throw CloudDataSchemaError.unsupportedVersion(storedVersion)
                }

                var tombstones = Self.eventTombstones(in: cloud)
                var tombstoneBases = DataManager.eventTombstoneBases(in: cloud)
                tombstones.formUnion(locallyDeletedIDs)
                for id in locallyDeletedIDs where tombstoneBases[id] == nil {
                    if let event = baseByID[id] {
                        tombstoneBases[id] = DataManager.eventContentFingerprint(event)
                    }
                }
                // Preserve a genuine offline edit racing a remote delete while
                // continuing to reject an unchanged stale replay.
                if mayRestoreTombstones {
                    let restored = explicitlyRestoredIDs.union(locallyEditedIDs)
                    tombstones.subtract(restored)
                    for id in restored { tombstoneBases.removeValue(forKey: id) }
                }
                var remote: [CustomEvent] = []
                var canonicalRemote: [CustomEvent] = []
                var canonicalTimestamp = Date.distantPast
                if let blob = cloud["events"] as? String {
                    canonicalRemote = try encryption.decrypt(
                        blob,
                        as: [CustomEvent].self,
                        userId: userId
                    )
                        .filter { !tombstones.contains($0.id.uuidString) }
                    remote = canonicalRemote
                    canonicalTimestamp = (cloud["eventsUpdatedAt"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                }
                if let legacy = try Self.decodeLegacyEvents(
                        in: root,
                        encryption: encryption,
                        userId: userId
                    ) {
                    let eventsTimestamp = (root["eventsUpdatedAt"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                    let releasedTimestamp = (root["eventsLastUpdated"] as? Timestamp)?.dateValue()
                        ?? .distantPast
                    let domainTimestamp = max(eventsTimestamp, releasedTimestamp)
                    let legacyTimestamp = domainTimestamp == .distantPast
                        ? ((root["lastUpdated"] as? Timestamp)?.dateValue() ?? .distantPast)
                        : domainTimestamp
                    let resolved = DataManager.resolvingEventTombstones(
                        legacy,
                        tombstones: tombstones,
                        bases: tombstoneBases
                    )
                    var resolvedTombstones = tombstones
                    resolvedTombstones.subtract(resolved.restoredIDs)
                    let resolvedLegacy = resolved.value.filter {
                        !resolvedTombstones.contains($0.id.uuidString)
                    }
                    let canonicalIsAuthoritative = cloud["events"] is String
                        && cloud["eventsInitialized"] as? Bool != false
                    if canonicalIsAuthoritative,
                       resolvedLegacy != remote,
                       !DataManager.eventValuesDifferOnlyByVerifiedRestorations(
                           resolvedLegacy,
                           remote,
                           restoredIDs: resolved.restoredIDs
                       ),
                       DataManager.importedTimestampOrderingIsAmbiguous(
                           legacyTimestamp,
                           canonicalTimestamp
                       ) {
                        throw CloudDataSchemaError.corruptPayload(
                            "ambiguous future events timestamp"
                        )
                    }
                    if cloud["events"] == nil || legacyTimestamp > canonicalTimestamp {
                        tombstones.subtract(resolved.restoredIDs)
                        for id in resolved.restoredIDs {
                            tombstoneBases.removeValue(forKey: id)
                        }
                        let legacyIDs = Set(resolved.value.map { $0.id })
                        for event in canonicalRemote where !legacyIDs.contains(event.id) {
                            let id = event.id.uuidString
                            tombstones.insert(id)
                            if tombstoneBases[id] == nil {
                                tombstoneBases[id] = DataManager.eventContentFingerprint(event)
                            }
                        }
                        remote = resolvedLegacy
                    }
                }
                let merged = CustomEventsManager.mergeEvents(
                    base: base,
                    local: events.filter { !tombstones.contains($0.id.uuidString) },
                    remote: remote
                ).filter { !tombstones.contains($0.id.uuidString) }
                let blob = try encryption.encrypt(merged, userId: userId)
                cloud["schemaVersion"] = Self.schemaVersion
                cloud["events"] = blob
                cloud["eventsInitialized"] = true
                cloud["eventTombstones"] = tombstones.sorted()
                cloud["eventTombstoneBases"] = tombstoneBases
                cloud["eventsUpdatedAt"] = FieldValue.serverTimestamp()
                transaction.setData([
                    "uid": userId,
                    "cloudDataV5": cloud,
                    "eventsEncrypted": true,
                    "customEvents": blob,
                    "eventsUpdatedAt": FieldValue.serverTimestamp(),
                    "eventsLastUpdated": FieldValue.serverTimestamp()
                ], forDocument: reference, merge: true)
                return blob
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        guard let committedBlob = result as? String else {
            throw CloudDataSchemaError.corruptPayload("events transaction")
        }
        let committedEvents = try encryption.decrypt(
            committedBlob,
            as: [CustomEvent].self,
            userId: userId
        )
        Self.snapshots[userId] = CloudSnapshot(
            events: committedEvents,
            isEncrypted: true,
            isCanonical: true
        )
        Self.usersNeedingRewrite.remove(userId)
    }

    private func clearPendingSave(_ saveID: UUID, for userId: String) {
        guard Self.pendingSaves[userId]?.id == saveID else { return }
        Self.pendingSaves[userId] = nil
    }

    static func quiesceWrites(
        for userId: String,
        timeout: Duration
    ) async -> Bool {
        guard let pending = pendingSaves[userId] else { return true }
        pending.task.cancel()
        let outcomes = AsyncStream<Bool> { continuation in
            Task { @MainActor in
                _ = try? await pending.task.value
                continuation.yield(true)
                continuation.finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                continuation.yield(false)
                continuation.finish()
            }
        }
        var completed = false
        for await result in outcomes {
            completed = result
            break
        }
        guard completed else { return false }
        if pendingSaves[userId]?.id == pending.id {
            pendingSaves[userId] = nil
        }
        return true
    }

    private func userDocument(for userId: String) -> DocumentReference {
        firestore.collection("users").document(userId)
    }

    nonisolated static func eventFromDict(_ eventDict: [String: Any]) -> CustomEvent? {
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
            let repeatPattern      = repeatPatternRaw == "Weekly"
                ? RepeatPattern.weekly
                : RepeatPattern(rawValue: repeatPatternRaw),
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

    nonisolated private static func decodeLegacyEvents(
        in data: [String: Any],
        encryption: EncryptionService,
        userId: String
    ) throws -> [CustomEvent]? {
        guard data["customEvents"] != nil else { return nil }
        if data["eventsEncrypted"] as? Bool == true {
            guard let blob = data["customEvents"] as? String else {
                throw EncryptionError.invalidData
            }
            return try encryption.decrypt(blob, as: [CustomEvent].self, userId: userId)
        }
        guard let dictionaries = data["customEvents"] as? [[String: Any]] else {
            throw EncryptionError.invalidData
        }
        let events = dictionaries.compactMap(eventFromDict)
        guard events.count == dictionaries.count else { throw EncryptionError.invalidData }
        return events
    }

    nonisolated private static func version5CloudData(
        in root: [String: Any]
    ) throws -> [String: Any]? {
        try DataManager.validatedVersion5CloudData(in: root)
    }

    nonisolated private static func eventTombstones(
        in cloud: [String: Any]
    ) -> Set<String> {
        Set(cloud["eventTombstones"] as? [String] ?? [])
    }
}
