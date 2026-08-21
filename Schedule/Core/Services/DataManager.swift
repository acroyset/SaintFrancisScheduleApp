//
//  DataManager.swift
//  Schedule
//
//  Cloud schema 5 stores encrypted application data in `cloudDataV5`. Released
//  builds used the top-level `encrypted` field as a Bool, while an unreleased
//  schema-4 port reused it as a map.  Keeping schema 5 in a separate field lets
//  old and new clients coexist without either representation replacing the
//  other. Legacy root fields are retained as recovery data during migration.
//

import CryptoKit
import FirebaseFirestore
import Foundation

enum CloudDataDeletionError: LocalizedError {
    case deletionInProgress
    case pendingWritesTimedOut

    var errorDescription: String? {
        switch self {
        case .deletionInProgress:
            "Cloud changes are paused while account deletion is in progress."
        case .pendingWritesTimedOut:
            "Account deletion stopped because pending cloud changes did not finish safely. Reconnect and try again."
        }
    }
}

enum CloudDataSchemaError: LocalizedError {
    case unsupportedVersion(Int)
    case corruptPayload(String)
    case concurrentMigrationChange

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This cloud data was written by a newer app version (schema \(version)). Update Schedule before syncing."
        case .corruptPayload(let domain):
            "The encrypted cloud \(domain) could not be read. Recovery data was left untouched."
        case .concurrentMigrationChange:
            "Cloud data changed on another device during migration. No source data was removed; retry sync."
        }
    }
}

@MainActor
class DataManager: ObservableObject {
    private let db = Firestore.firestore()
    private let encryption = EncryptionService.shared
    private(set) var lastScheduleLoadWasAuthoritative = false

    nonisolated private static let cloudField = "cloudDataV5"
    nonisolated private static let transitionalCloudField = "cloudData"
    nonisolated private static let cloudSchemaVersion = 5
    nonisolated private static let sessionMigrationVersion = 5
    nonisolated private static let usageSessionSchemaVersion = 2
    nonisolated private static let maximumImportedTimestampSkew: TimeInterval = 5 * 60

    private struct CloudSnapshot: Equatable {
        let classes: [ClassItem]
        let theme: ThemeColors
        let isSecondLunch: [Bool]
        let isEncrypted: Bool
        let isCanonical: Bool
    }

    private struct SchedulePayload: Codable {
        let classes: [ClassItem]
        let theme: ThemeColors
        let isSecondLunch: [Bool]
    }

    private struct ScheduleSource {
        let value: ([ClassItem], ThemeColors, [Bool])
        let updatedAt: Date
        let restoredClassIDs: Set<String>

        init(
            value: ([ClassItem], ThemeColors, [Bool]),
            updatedAt: Date,
            restoredClassIDs: Set<String> = []
        ) {
            self.value = value
            self.updatedAt = updatedAt
            self.restoredClassIDs = restoredClassIDs
        }
    }

    /// Tracks which schedule fields a legacy writer actually supplied. Older
    /// clients could update only one top-level field, so decoded defaults for a
    /// missing field must never outrank an older complete recovery source.
    private struct LegacyScheduleCandidate {
        let source: ScheduleSource
        let carriesClasses: Bool
        let carriesTheme: Bool
        let carriesLunch: Bool
    }

    private struct EventSource {
        let value: [CustomEvent]
        let updatedAt: Date
        let restoredEventIDs: Set<String>

        init(
            value: [CustomEvent],
            updatedAt: Date,
            restoredEventIDs: Set<String> = []
        ) {
            self.value = value
            self.updatedAt = updatedAt
            self.restoredEventIDs = restoredEventIDs
        }
    }

    private struct LegacySyncSnapshot {
        let state: [String: Any]?
        let schedule: [String: Any]?
        let events: [String: Any]?
    }

    private final class ListenerState {
        var latestTimestamp: Date = .distantPast
        var hasDeliveredValue = false
        var latestSchedule: CloudSnapshot?
        var latestWasAuthoritative: Bool?
    }

    private enum CloudField: Hashable {
        case classes
        case theme
        case isSecondLunch
    }

    private struct PendingSave {
        let id: UUID
        let task: Task<Void, Error>
    }

    private struct PendingMigration {
        let id: UUID
        let task: Task<Void, Error>
    }

    private struct CachedRoot {
        let data: [String: Any]
        let cachedAt: Date
    }

    private static var snapshots: [String: CloudSnapshot] = [:]
    private static var fieldsNeedingRewrite: [String: Set<CloudField>] = [:]
    private static var pendingSaves: [String: PendingSave] = [:]
    private static var pendingMigrations: [String: PendingMigration] = [:]
    private static var cloudWriteBlocks: [String: CloudDataSchemaError] = [:]
    private static var deletingUsers: Set<String> = []
    private static var validatedRoots: [String: CachedRoot] = [:]

    // MARK: - Schedule save/load

    func saveToCloud(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        for userId: String
    ) async throws {
        let previousTask = Self.pendingSaves[userId]?.task
        let saveID = UUID()
        let task = Task { @MainActor [self] in
            if let previousTask {
                _ = try? await previousTask.value
            }
            try Self.assertCloudWriteAllowed(for: userId)
            let hadTrustedBaseline = Self.snapshots[userId] != nil
            // A save without a decoded baseline cannot distinguish a genuine
            // delete from stale device state. Establish the server baseline
            // first so the transaction below always performs a three-way merge
            // instead of replacing an existing schedule wholesale.
            if Self.snapshots[userId] == nil {
                try await loadScheduleBaselineWhenAvailable(for: userId)
            }
            try await writeChangedScheduleFields(
                classes: classes,
                theme: theme,
                isSecondLunch: isSecondLunch,
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

    private func loadScheduleBaselineWhenAvailable(for userId: String) async throws {
        while true {
            do {
                _ = try await loadFromCloud(for: userId)
                return
            } catch where Self.isFirestoreUnavailable(error) {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func loadFromCloud(for userId: String) async throws -> ([ClassItem], ThemeColors, [Bool]) {
        lastScheduleLoadWasAuthoritative = false
        try await migrateLegacyUserDocumentIfNeeded(for: userId)
        let data: [String: Any]
        if let cached = Self.recentValidatedRootData(for: userId) {
            data = cached
        } else {
            data = try await userDocument(for: userId).getDocument().data() ?? [:]
            Self.cacheValidatedRoot(data, for: userId)
        }
        try Self.validateVersion5Container(in: data)
        guard !data.isEmpty else {
            Self.snapshots[userId] = nil
            Self.fieldsNeedingRewrite[userId] = nil
            return ([], defaultTheme, [false, false])
        }

        if let futureVersion = Self.unsupportedTransitionalVersion(in: data) {
            let error = CloudDataSchemaError.unsupportedVersion(futureVersion)
            Self.cloudWriteBlocks[userId] = error
            throw error
        }
        if let cloud = Self.version5CloudData(in: data) {
            let version = Self.schemaVersion(in: cloud)
            if version > Self.cloudSchemaVersion {
                let error = CloudDataSchemaError.unsupportedVersion(version)
                Self.cloudWriteBlocks[userId] = error
                throw error
            }
            guard version == Self.cloudSchemaVersion else {
                throw CloudDataSchemaError.corruptPayload("schema")
            }
            do {
                let loaded = try decodeCanonicalSchedule(cloud, userId: userId)
                lastScheduleLoadWasAuthoritative = Self.canonicalScheduleIsAuthoritative(cloud)
                cacheSchedule(loaded, for: userId, canonical: true)
                return loaded
            } catch {
                Self.noteCloudReadFailure(error, for: userId)
                throw error
            }
        }

        if let source = try legacyScheduleSource(in: data, userId: userId) {
            lastScheduleLoadWasAuthoritative = data["scheduleInitialized"] as? Bool != false
            cacheSchedule(source.value, for: userId, canonical: false)
            Self.fieldsNeedingRewrite[userId] = [.classes, .theme, .isSecondLunch]
            return source.value
        }
        return ([], defaultTheme, [false, false])
    }

    func observeSchedule(
        for userId: String,
        onChange: @escaping @MainActor (
            Result<([ClassItem], ThemeColors, [Bool], Bool), Error>
        ) -> Void
    ) -> CloudSyncObservation {
        let state = ListenerState()
        let listener = userDocument(for: userId).addSnapshotListener(
            includeMetadataChanges: true
        ) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    onChange(.failure(error))
                    return
                }
                guard let snapshot else { return }
                if !snapshot.exists {
                    // An empty cache is not proof that the server document was
                    // deleted. Wait for the server-confirmed snapshot so a
                    // cold/offline listener cannot replace device-only data.
                    guard !snapshot.metadata.isFromCache else { return }
                    state.hasDeliveredValue = false
                    state.latestTimestamp = .distantPast
                    state.latestSchedule = nil
                    state.latestWasAuthoritative = nil
                    let missing = Self.scheduleStateForMissingRoot(for: userId)
                    onChange(.success(missing))
                    return
                }
                guard let data = snapshot.data() else { return }
                // Local server-timestamp sentinels are exposed as unresolved
                // values until Firestore commits them. Validate the committed
                // snapshot instead of turning a normal pending write into a
                // durable corrupt-data fence.
                guard !snapshot.metadata.hasPendingWrites else { return }
                do {
                    Self.cacheValidatedRoot(data, for: userId)
                    let effective = try self.effectiveSchedule(in: data, userId: userId)
                    let isCanonical = Self.version5CloudData(in: data) != nil
                    let isAuthoritative = Self.scheduleIsAuthoritative(in: data)
                    let candidate = CloudSnapshot(
                        classes: effective.value.0,
                        theme: effective.value.1,
                        isSecondLunch: effective.value.2,
                        isEncrypted: true,
                        isCanonical: isCanonical
                    )
                    // Firestore delivers committed snapshots in document order.
                    // Embedded timestamps are user/imported data and may be far
                    // in the future; using them as a permanent high-water mark
                    // can suppress every later real edit. Deduplicate identical
                    // visible state instead, while still delivering authority
                    // changes for an otherwise identical schedule.
                    guard state.latestSchedule != candidate
                            || state.latestWasAuthoritative != isAuthoritative else {
                        return
                    }
                    state.hasDeliveredValue = true
                    state.latestTimestamp = max(state.latestTimestamp, effective.updatedAt)
                    state.latestSchedule = candidate
                    state.latestWasAuthoritative = isAuthoritative
                    self.cacheSchedule(
                        effective.value,
                        for: userId,
                        canonical: isCanonical
                    )
                    onChange(.success((
                        effective.value.0,
                        effective.value.1,
                        effective.value.2,
                        isAuthoritative
                    )))

                    if self.scheduleNeedsLegacyReconciliation(in: data, userId: userId) {
                        Task { @MainActor [weak self] in
                            try? await self?.migrateLegacyUserDocumentIfNeeded(for: userId)
                        }
                    }
                } catch {
                    Self.noteCloudReadFailure(error, for: userId)
                    onChange(.failure(error))
                }
            }
        }
        return CloudSyncObservation { listener.remove() }
    }

    // MARK: - Policy and usage sessions

    func recordPolicyAcceptance(for userId: String, version: String) async throws {
        try await migrateLegacyUserDocumentIfNeeded(for: userId)
        try await userDocument(for: userId).setData([
            "uid": userId,
            "privacyPolicy": [
                "accepted": true,
                "version": version,
                "timestamp": FieldValue.serverTimestamp()
            ]
        ], merge: true)
    }

    func checkPolicyNeedsRenewal(for userId: String, currentVersion: String) async throws -> Bool {
        try await migrateLegacyUserDocumentIfNeeded(for: userId)
        guard let data = try await userDocument(for: userId).getDocument().data(),
              let policy = data["privacyPolicy"] as? [String: Any],
              policy["accepted"] as? Bool == true,
              let stored = policy["version"] as? String else {
            return true
        }
        return stored < currentVersion
    }

    func appendUsageSessionToCloud(_ session: UsageSessionRecord, for userId: String) async throws {
        try Self.assertCloudWriteAllowed(for: userId)
        let sessionData: [String: Any] = [
            "schemaVersion": Self.usageSessionSchemaVersion,
            "id": session.id,
            "startedAt": Timestamp(date: session.startedAt),
            "endedAt": Timestamp(date: session.endedAt),
            "appVersion": session.appVersion,
            "lastPage": session.lastPage ?? NSNull(),
            "pageDurations": session.pageDurations,
            "featureDurations": session.featureDurations,
            "featureViewCounts": session.featureViewCounts,
            "itemActionCounts": session.itemActionCounts,
            "newsTabDurations": session.newsTabDurations,
            "newsTabViewCounts": session.newsTabViewCounts,
            "notificationsEnabled": session.notificationsEnabled,
            "liveActivitiesEnabled": session.liveActivitiesEnabled,
            "liveActivityActive": session.liveActivityActive
        ]
        let userRef = userDocument(for: userId)
        let sessionRef = sessionsCollection(for: userId).document(session.id)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let root = try transaction.getDocument(userRef).data() ?? [:]
                if let clearedAt = Self.timestampOrNil(root["usageSessionsClearedAt"]),
                   session.startedAt <= clearedAt {
                    // This is an offline snapshot from before an explicit
                    // clear. Treat the write as already satisfied rather than
                    // resurrecting data the user deleted.
                    return false
                }
                let existing = try transaction.getDocument(sessionRef).data()
                if let existing {
                    if let version = try Self.exactUsageSessionSchemaVersion(in: existing),
                       version > Self.usageSessionSchemaVersion {
                        // A newer app owns this logical record. Even a later
                        // local end time does not authorize this client to
                        // rewrite unknown fields or downgrade its schema.
                        return false
                    }
                    if Self.usageSessionEndedAt(existing) > session.endedAt {
                        return false
                    }
                }
                transaction.setData(sessionData, forDocument: sessionRef, merge: true)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func clearUsageStats(for userId: String) async throws {
        try Self.assertCloudWriteAllowed(for: userId)
        try await migrateLegacyUserDocumentIfNeeded(for: userId)
        // Commit the tombstone and empty every released root representation in
        // one transaction. If subcollection deletion is interrupted, later
        // migration/append paths still reject every pre-clear record.
        let userRef = userDocument(for: userId)
        let stateRef = legacyStateDocument(for: userId)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let rootSnapshot = try transaction.getDocument(userRef)
                let stateSnapshot = try transaction.getDocument(stateRef)
                var rootUsage = rootSnapshot.data()?["usageStats"] as? [String: Any] ?? [:]
                rootUsage["sessions"] = []
                var rootSessions = rootSnapshot.data()?["sessions"] as? [String: Any] ?? [:]
                rootSessions["records"] = []
                transaction.setData([
                    "usageStats": rootUsage,
                    "sessions": rootSessions,
                    "usageSessionsClearedAt": FieldValue.serverTimestamp(),
                    "usageStatsUpdatedAt": FieldValue.serverTimestamp(),
                    "usageSessionEmbeddedDigest": Self.usageSessionDigest([]),
                    "usageSessionLegacyUpdatedAt": FieldValue.serverTimestamp(),
                    "usageSessionMigrationVersion": Self.sessionMigrationVersion
                ], forDocument: userRef, merge: true)
                if rootSnapshot.exists {
                    transaction.updateData([
                        FieldPath(["usageStats.sessions"]): FieldValue.delete()
                    ] as [AnyHashable: Any], forDocument: userRef)
                }
                if stateSnapshot.exists {
                    var stateUsage = stateSnapshot.data()?["usageStats"] as? [String: Any] ?? [:]
                    stateUsage["sessions"] = []
                    var stateSessions = stateSnapshot.data()?["sessions"] as? [String: Any] ?? [:]
                    stateSessions["records"] = []
                    transaction.setData([
                        "usageStats": stateUsage,
                        "sessions": stateSessions
                    ], forDocument: stateRef, merge: true)
                    transaction.updateData([
                        FieldPath(["usageStats.sessions"]): FieldValue.delete()
                    ] as [AnyHashable: Any], forDocument: stateRef)
                }
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        let committedRoot = try await userRef.getDocument().data() ?? [:]
        guard let clearedAt = Self.timestampOrNil(committedRoot["usageSessionsClearedAt"]) else {
            throw CloudDataSchemaError.corruptPayload("usage clear tombstone")
        }
        // Delete only records at or before the committed tombstone. A new
        // session appended on another device after the clear transaction must
        // survive even if it lands before this cleanup query finishes.
        try await deleteCanonicalSessions(for: userId, startingOnOrBefore: clearedAt)
        try await deleteSessions(
            in: legacyStateDocument(for: userId).collection("sessions"),
            startingOnOrBefore: clearedAt
        )
    }

    // MARK: - Account data deletion

    /// Atomically freezes the user root and creates a durable server-owned
    /// deletion request. The app deliberately does not delete any user data:
    /// the retryable backend removes Firebase Auth first, then recursively
    /// deletes Firestore. If this call or the app is interrupted, the account
    /// data remains intact and the durable request can be resumed safely.
    func requestUserDataDeletion(for userId: String) async throws {
        guard !Self.deletingUsers.contains(userId) else {
            throw CloudDataDeletionError.deletionInProgress
        }
        Self.deletingUsers.insert(userId)

        do {
            if let save = Self.pendingSaves[userId]?.task {
                save.cancel()
                guard await Self.taskCompletes(save, within: .seconds(10)) else {
                    throw CloudDataDeletionError.pendingWritesTimedOut
                }
                Self.pendingSaves[userId] = nil
            }
            if let migration = Self.pendingMigrations[userId]?.task {
                migration.cancel()
                guard await Self.taskCompletes(migration, within: .seconds(10)) else {
                    throw CloudDataDeletionError.pendingWritesTimedOut
                }
                Self.pendingMigrations[userId] = nil
            }
            guard await CloudEventsDataManager.quiesceWrites(
                for: userId,
                timeout: .seconds(10)
            ) else {
                throw CloudDataDeletionError.pendingWritesTimedOut
            }

            let userRef = userDocument(for: userId)
            let requestRef = accountDeletionRequestDocument(for: userId)
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let request = try transaction.getDocument(requestRef)
                    if request.exists {
                        // A previous attempt already committed the durable
                        // request. Treat retries as success; the backend and
                        // scheduled recovery worker are idempotent.
                        return true
                    }

                    let user = try transaction.getDocument(userRef)
                    let deletionMarker: [String: Any] = [
                        "state": "requested",
                        "workflowVersion": 1,
                        "requestedAt": FieldValue.serverTimestamp()
                    ]
                    if user.exists {
                        transaction.updateData([
                            "accountDeletion": deletionMarker
                        ], forDocument: userRef)
                    } else {
                        transaction.setData([
                            "accountDeletion": deletionMarker
                        ], forDocument: userRef)
                    }
                    transaction.setData(deletionMarker, forDocument: requestRef)
                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            Self.snapshots[userId] = nil
            Self.fieldsNeedingRewrite[userId] = nil
            Self.validatedRoots[userId] = nil
        } catch {
            Self.deletingUsers.remove(userId)
            throw error
        }
    }

    // MARK: - Migration

    func migrateLegacyUserDocumentIfNeeded(for userId: String) async throws {
        // A previous read may have fenced writes because it saw corrupt or
        // future data. Migration must still be allowed to re-read the root so
        // a repair from another device can clear that fence. Only destructive
        // account deletion blocks reads/migration outright.
        try Self.assertUserIsNotBeingDeleted(userId)
        if let pending = Self.pendingMigrations[userId] {
            try await pending.task.value
            return
        }

        let migrationID = UUID()
        let task = Task { @MainActor [self] in
            for attempt in 0..<3 {
                do {
                    try await performLegacyUserDocumentMigrationIfNeeded(for: userId)
                    return
                } catch CloudDataSchemaError.concurrentMigrationChange where attempt < 2 {
                    continue
                }
            }
        }
        Self.pendingMigrations[userId] = PendingMigration(id: migrationID, task: task)
        do {
            try await task.value
            Self.cloudWriteBlocks[userId] = nil
            clearPendingMigration(migrationID, for: userId)
        } catch {
            if let schemaError = error as? CloudDataSchemaError {
                if case .concurrentMigrationChange = schemaError {
                    // A transient root race is retried on the next sync; it is
                    // not a durable reason to fence every later migration.
                } else {
                    Self.cloudWriteBlocks[userId] = schemaError
                }
            }
            clearPendingMigration(migrationID, for: userId)
            throw error
        }
    }

    private func performLegacyUserDocumentMigrationIfNeeded(for userId: String) async throws {
        let userRef = userDocument(for: userId)
        let userSnapshot = try await userRef.getDocument()
        let userData = userSnapshot.data() ?? [:]
        try Self.validateVersion5Container(in: userData)
        if let futureVersion = Self.unsupportedTransitionalVersion(in: userData) {
            throw CloudDataSchemaError.unsupportedVersion(futureVersion)
        }
        let initialCanonicalCloud = userData[Self.cloudField] as? [String: Any]
        let hasVersionedCloud = initialCanonicalCloud != nil
        let existingCloud = Self.version5CloudData(in: userData) ?? [:]
        let version = Self.schemaVersion(in: existingCloud)
        if version > Self.cloudSchemaVersion {
            throw CloudDataSchemaError.unsupportedVersion(version)
        }

        let cloudSchedulePresence = Self.hasAnyCloudScheduleField(existingCloud)
        let cloudEventsPresence = existingCloud["events"] != nil
        let canonicalSchedule: Attempt<([ClassItem], ThemeColors, [Bool])> = cloudSchedulePresence
            ? tryResult { try decodeCanonicalSchedule(existingCloud, userId: userId) }
            : Attempt(value: nil, error: nil)
        let canonicalEvents: Attempt<[CustomEvent]> = cloudEventsPresence
            ? tryResult { try decodeCanonicalEvents(existingCloud, userId: userId) }
            : Attempt(value: nil, error: nil)
        let cloudScheduleValue = canonicalSchedule.value
        let cloudEventsValue = canonicalEvents.value
        let corruptVersion5Recovery = hasVersionedCloud
            && (canonicalSchedule.error != nil || canonicalEvents.error != nil)
            ? existingCloud
            : nil

        let rootSchedule = tryOptionalResult {
            try legacyScheduleSource(
                in: userData,
                userId: userId,
                fillingMissingFrom: cloudScheduleValue
            )
        }
        let rootEvents = tryOptionalResult {
            try legacyEventSource(in: userData, userId: userId)
        }
        let cloudScheduleTime = Self.timestamp(existingCloud["scheduleUpdatedAt"])
        let cloudEventsTime = Self.timestamp(existingCloud["eventsUpdatedAt"])
        let canonicalScheduleIsAuthoritative = cloudScheduleValue != nil
            && Self.canonicalScheduleIsAuthoritative(existingCloud)
        let canonicalEventsAreAuthoritative = cloudEventsValue != nil
            && Self.canonicalEventsAreAuthoritative(existingCloud)

        // A released client writes device-clock timestamps. When its decoded
        // value conflicts with an authoritative canonical value, a timestamp
        // years ahead cannot safely prove which copy is newer. Stop before the
        // fast path or any migration write so both copies remain recoverable.
        if canonicalScheduleIsAuthoritative,
           let canonical = cloudScheduleValue,
           let root = rootSchedule.value {
            try validateUnambiguousScheduleOrdering([
                ScheduleSource(value: canonical, updatedAt: cloudScheduleTime),
                root
            ])
        }
        if canonicalEventsAreAuthoritative,
           let canonical = cloudEventsValue,
           let root = rootEvents.value {
            try validateUnambiguousEventOrdering([
                EventSource(value: canonical, updatedAt: cloudEventsTime),
                root
            ])
        }

        let newerRootSchedule = rootSchedule.value.flatMap { source -> ScheduleSource? in
            guard let canonical = cloudScheduleValue,
                  source.updatedAt > cloudScheduleTime,
                  !Self.scheduleValuesEqual(source.value, canonical) else { return nil }
            return source
        }
        let newerRootEvents = rootEvents.value.flatMap { source -> EventSource? in
            guard let canonical = cloudEventsValue,
                  source.updatedAt > cloudEventsTime,
                  source.value != canonical else { return nil }
            return source
        }
        let newerRootEstablishesEventAuthority = !canonicalEventsAreAuthoritative
            && (rootEvents.value?.updatedAt ?? .distantPast) > cloudEventsTime
        let newerRootEstablishesScheduleAuthority = !canonicalScheduleIsAuthoritative
            && Self.legacyScheduleCarriesClasses(userData)
            && (rootSchedule.value?.updatedAt ?? .distantPast) > cloudScheduleTime

        let marker = try Self.migrationMarker(
            in: userData,
            key: "usageSessionMigrationVersion"
        )
        let syncMarker = try Self.migrationMarker(
            in: userData,
            key: "legacySyncMigrationVersion"
        )
        let embeddedRootSessions = Self.embeddedUsageSessions(in: userData)
        let migratableEmbeddedRootSessions = Self.embeddedUsageSessionsForMigration(
            in: userData
        )
        let embeddedRootDigest = Self.usageSessionDigest(embeddedRootSessions)
        let storedEmbeddedDigest = userData["usageSessionEmbeddedDigest"] as? String
        let hasEmbeddedRootSessionField = Self.hasEmbeddedUsageSessionField(in: userData)
        let legacySessionUpdatedAt = Self.timestampOrNil(userData["usageStatsUpdatedAt"])
        let storedLegacySessionUpdatedAt = Self.timestampOrNil(
            userData["usageSessionLegacyUpdatedAt"]
        )
        let rootSessionsNeedReconciliation = hasEmbeddedRootSessionField && (
            (!embeddedRootSessions.isEmpty && embeddedRootDigest != storedEmbeddedDigest)
                || (legacySessionUpdatedAt ?? .distantPast)
                    > (storedLegacySessionUpdatedAt ?? .distantPast)
        )
        let completeValidV5 = version == Self.cloudSchemaVersion
            && cloudScheduleValue != nil
            && cloudEventsValue != nil
        let releasedMirrorNeedsSanitization = releasedMirrorNeedsTombstoneSanitization(
            root: userData,
            cloud: existingCloud,
            userId: userId
        )
        let needsReleasedMirror = (canonicalScheduleIsAuthoritative
                && !Self.hasCompleteReleasedScheduleMirror(userData))
            || (canonicalEventsAreAuthoritative
                && !Self.hasCompleteReleasedEventsMirror(userData))
            || releasedMirrorNeedsSanitization
        let cloudTimestampsNeedNormalization =
            Self.isImplausiblyFutureTimestamp(existingCloud["scheduleUpdatedAt"])
            || Self.isImplausiblyFutureTimestamp(existingCloud["eventsUpdatedAt"])

        if completeValidV5,
           newerRootSchedule == nil,
           newerRootEvents == nil,
           !newerRootEstablishesScheduleAuthority,
           !newerRootEstablishesEventAuthority,
           !needsReleasedMirror,
           !cloudTimestampsNeedNormalization,
           !rootSessionsNeedReconciliation,
           marker == Self.sessionMigrationVersion,
           syncMarker == Self.cloudSchemaVersion {
            Self.cacheValidatedRoot(userData, for: userId)
            return
        }

        // A root write newer than canonical but malformed must not be silently
        // ignored. The existing canonical copy remains untouched for recovery.
        if completeValidV5 {
            if Self.legacyScheduleClaimed(in: userData),
               Self.legacyScheduleTimestamp(in: userData) > cloudScheduleTime,
               rootSchedule.error != nil,
               !releasedMirrorNeedsSanitization {
                throw CloudDataSchemaError.corruptPayload("legacy schedule")
            }
            if Self.legacyEventsClaimed(in: userData),
               Self.legacyEventTimestamp(in: userData) > cloudEventsTime,
               rootEvents.error != nil,
               !releasedMirrorNeedsSanitization {
                throw CloudDataSchemaError.corruptPayload("legacy events")
            }
        }

        var oldStateData: [String: Any] = [:]
        var oldScheduleData: [String: Any]?
        var oldEventsData: [String: Any]?
        var oldSessionDocuments: [QueryDocumentSnapshot] = []
        var legacySyncSnapshot: LegacySyncSnapshot?

        if marker != Self.sessionMigrationVersion
            || syncMarker != Self.cloudSchemaVersion
            || !completeValidV5 {
            let oldStateRef = legacyStateDocument(for: userId)
            let oldStateSnapshot = try await oldStateRef.getDocument()
            let oldScheduleSnapshot = try await legacyScheduleDocument(for: userId).getDocument()
            let oldEventsSnapshot = try await legacyEventsDocument(for: userId).getDocument()
            oldSessionDocuments = try await oldStateRef.collection("sessions").getDocuments().documents
            oldStateData = oldStateSnapshot.data() ?? [:]
            try Self.validateEmbeddedUsageCarriers(in: oldStateData)
            oldScheduleData = oldScheduleSnapshot.data()
            oldEventsData = oldEventsSnapshot.data()
            legacySyncSnapshot = LegacySyncSnapshot(
                state: oldStateSnapshot.data(),
                schedule: oldScheduleSnapshot.data(),
                events: oldEventsSnapshot.data()
            )
        }

        let stateSchedule = tryOptionalResult {
            try legacyScheduleSource(
                in: oldStateData,
                userId: userId,
                fillingMissingFrom: cloudScheduleValue
            )
        }
        let stateEvents = tryOptionalResult {
            try legacyEventSource(in: oldStateData, userId: userId)
        }
        let documentSchedule = tryOptionalResult {
            try encryptedScheduleDocumentSource(
                oldScheduleData,
                userId: userId,
                reconcilingIDsWith: cloudScheduleValue?.0
            )
        }
        let documentEvents = tryOptionalResult {
            try encryptedEventDocumentSource(oldEventsData, userId: userId)
        }

        // Retained /sync documents are a recovery source, not disposable
        // cache. Never fence them behind marker 5 when they claim a domain but
        // cannot be decoded; a later/newer valid source must not make that
        // corruption look like an absent domain.
        if Self.legacyScheduleClaimed(in: oldStateData), stateSchedule.error != nil {
            throw CloudDataSchemaError.corruptPayload("recovery schedule")
        }
        if oldScheduleData?["payload"] != nil, documentSchedule.error != nil {
            throw CloudDataSchemaError.corruptPayload("recovery schedule")
        }
        if Self.legacyEventsClaimed(in: oldStateData), stateEvents.error != nil {
            throw CloudDataSchemaError.corruptPayload("recovery events")
        }
        if oldEventsData?["payload"] != nil, documentEvents.error != nil {
            throw CloudDataSchemaError.corruptPayload("recovery events")
        }

        if !userSnapshot.exists,
           oldStateData.isEmpty,
           oldScheduleData == nil,
           oldEventsData == nil,
           oldSessionDocuments.isEmpty {
            Self.cacheValidatedRoot([:], for: userId)
            return
        }

        let legacyScheduleCandidates = [
            rootSchedule.value.map {
                Self.legacyScheduleCandidate(source: $0, data: userData)
            },
            documentSchedule.value.map {
                LegacyScheduleCandidate(
                    source: $0,
                    carriesClasses: true,
                    carriesTheme: true,
                    carriesLunch: true
                )
            },
            stateSchedule.value.map {
                Self.legacyScheduleCandidate(source: $0, data: oldStateData)
            }
        ].compactMap { $0 }
        var scheduleOrderingSources = legacyScheduleCandidates.map(\.source)
        if canonicalScheduleIsAuthoritative, let canonical = cloudScheduleValue {
            scheduleOrderingSources.append(
                ScheduleSource(value: canonical, updatedAt: cloudScheduleTime)
            )
        }
        try validateUnambiguousScheduleOrdering(scheduleOrderingSources)
        let bestLegacyScheduleCandidate = legacyScheduleCandidates.max {
            $0.source.updatedAt < $1.source.updatedAt
        }

        var selectedSchedule: ScheduleSource
        var selectedLegacyScheduleCandidate: LegacyScheduleCandidate?
        let scheduleUsesCanonical: Bool
        if let canonical = cloudScheduleValue {
            let canonicalSource = ScheduleSource(value: canonical, updatedAt: cloudScheduleTime)
            let legacyEstablishesAuthority = !canonicalScheduleIsAuthoritative
                && legacyScheduleCandidates.contains(where: { $0.carriesClasses })
            if let bestLegacyScheduleCandidate,
               bestLegacyScheduleCandidate.source.updatedAt > cloudScheduleTime,
               (!Self.scheduleValuesEqual(
                    bestLegacyScheduleCandidate.source.value,
                    canonical
                ) || legacyEstablishesAuthority) {
                selectedSchedule = bestLegacyScheduleCandidate.source
                selectedLegacyScheduleCandidate = bestLegacyScheduleCandidate
                scheduleUsesCanonical = false
            } else {
                selectedSchedule = canonicalSource
                scheduleUsesCanonical = true
            }
        } else if let bestLegacyScheduleCandidate {
            selectedSchedule = bestLegacyScheduleCandidate.source
            selectedLegacyScheduleCandidate = bestLegacyScheduleCandidate
            scheduleUsesCanonical = false
        } else {
            if cloudSchedulePresence && canonicalSchedule.error != nil {
                throw CloudDataSchemaError.corruptPayload("schedule")
            }
            if Self.legacyScheduleClaimed(in: userData), rootSchedule.error != nil {
                throw CloudDataSchemaError.corruptPayload("legacy schedule")
            }
            if Self.legacyScheduleClaimed(in: oldStateData), stateSchedule.error != nil {
                throw CloudDataSchemaError.corruptPayload("recovery schedule")
            }
            if oldScheduleData?["payload"] != nil, documentSchedule.error != nil {
                throw CloudDataSchemaError.corruptPayload("recovery schedule")
            }
            selectedSchedule = ScheduleSource(
                value: ([], defaultTheme, [false, false]),
                updatedAt: .distantPast
            )
            scheduleUsesCanonical = false
        }

        // A released/root-state writer can update only one schedule field. Do
        // not let decoded defaults for the other fields outrank an older,
        // complete root or /sync/schedule recovery source. A schema-4 combined
        // payload and a /sync/schedule payload both carry all three fields.
        if !scheduleUsesCanonical,
           var selectedCandidate = selectedLegacyScheduleCandidate {
            var value = selectedSchedule.value
            var restoredClassIDs = selectedSchedule.restoredClassIDs
            if !selectedCandidate.carriesClasses,
               let fallback = legacyScheduleCandidates
                .filter(\.carriesClasses)
                .max(by: { $0.source.updatedAt < $1.source.updatedAt }) {
                value.0 = fallback.source.value.0
                restoredClassIDs.formUnion(fallback.source.restoredClassIDs)
                selectedCandidate = LegacyScheduleCandidate(
                    source: selectedCandidate.source,
                    carriesClasses: true,
                    carriesTheme: selectedCandidate.carriesTheme,
                    carriesLunch: selectedCandidate.carriesLunch
                )
            }
            if !selectedCandidate.carriesTheme,
               let fallback = legacyScheduleCandidates
                .filter(\.carriesTheme)
                .max(by: { $0.source.updatedAt < $1.source.updatedAt }) {
                value.1 = fallback.source.value.1
                selectedCandidate = LegacyScheduleCandidate(
                    source: selectedCandidate.source,
                    carriesClasses: selectedCandidate.carriesClasses,
                    carriesTheme: true,
                    carriesLunch: selectedCandidate.carriesLunch
                )
            }
            if !selectedCandidate.carriesLunch,
               let fallback = legacyScheduleCandidates
                .filter(\.carriesLunch)
                .max(by: { $0.source.updatedAt < $1.source.updatedAt }) {
                value.2 = fallback.source.value.2
                selectedCandidate = LegacyScheduleCandidate(
                    source: selectedCandidate.source,
                    carriesClasses: selectedCandidate.carriesClasses,
                    carriesTheme: selectedCandidate.carriesTheme,
                    carriesLunch: true
                )
            }
            selectedSchedule = ScheduleSource(
                value: value,
                updatedAt: selectedSchedule.updatedAt,
                restoredClassIDs: restoredClassIDs
            )
            selectedLegacyScheduleCandidate = selectedCandidate
        }

        let selectedEvents: EventSource
        let eventsUseCanonical: Bool
        let legacyEventCandidates = [
            rootEvents.value,
            documentEvents.value,
            stateEvents.value
        ].compactMap { $0 }
        var eventOrderingSources = legacyEventCandidates
        if canonicalEventsAreAuthoritative, let canonical = cloudEventsValue {
            eventOrderingSources.append(
                EventSource(value: canonical, updatedAt: cloudEventsTime)
            )
        }
        try validateUnambiguousEventOrdering(eventOrderingSources)
        let bestLegacyEvents = legacyEventCandidates.reduce(nil as EventSource?) { current, candidate in
            guard let current else { return candidate }
            return candidate.updatedAt > current.updatedAt ? candidate : current
        }
        if let canonical = cloudEventsValue {
            let canonicalSource = EventSource(value: canonical, updatedAt: cloudEventsTime)
            if let bestLegacyEvents,
               bestLegacyEvents.updatedAt > cloudEventsTime,
               bestLegacyEvents.value != canonical {
                selectedEvents = bestLegacyEvents
                eventsUseCanonical = false
            } else {
                selectedEvents = canonicalSource
                eventsUseCanonical = true
            }
        } else if let bestLegacyEvents {
            selectedEvents = bestLegacyEvents
            eventsUseCanonical = false
        } else {
            if cloudEventsPresence && canonicalEvents.error != nil {
                throw CloudDataSchemaError.corruptPayload("events")
            }
            if Self.legacyEventsClaimed(in: userData), rootEvents.error != nil {
                throw CloudDataSchemaError.corruptPayload("legacy events")
            }
            if Self.legacyEventsClaimed(in: oldStateData), stateEvents.error != nil {
                throw CloudDataSchemaError.corruptPayload("recovery events")
            }
            if oldEventsData?["payload"] != nil, documentEvents.error != nil {
                throw CloudDataSchemaError.corruptPayload("recovery events")
            }
            selectedEvents = EventSource(value: [], updatedAt: .distantPast)
            eventsUseCanonical = false
        }

        var migratedCloud = existingCloud
        let resolvedCarrierDiffersFromCanonical = initialCanonicalCloud.map {
            Self.stableValue($0) != Self.stableValue(existingCloud)
        } ?? !existingCloud.isEmpty
        var cloudNeedsWrite = version != Self.cloudSchemaVersion
            || !hasVersionedCloud
            || resolvedCarrierDiffersFromCanonical
        if Self.isImplausiblyFutureTimestamp(existingCloud["scheduleUpdatedAt"]) {
            migratedCloud["scheduleUpdatedAt"] = FieldValue.serverTimestamp()
            cloudNeedsWrite = true
        }
        if Self.isImplausiblyFutureTimestamp(existingCloud["eventsUpdatedAt"]) {
            migratedCloud["eventsUpdatedAt"] = FieldValue.serverTimestamp()
            cloudNeedsWrite = true
        }
        var classTombstones = Self.classTombstones(in: existingCloud)
        var classTombstoneBases = Self.classTombstoneBases(in: existingCloud)
        if !scheduleUsesCanonical {
            classTombstones.subtract(selectedSchedule.restoredClassIDs)
            for id in selectedSchedule.restoredClassIDs {
                classTombstoneBases.removeValue(forKey: id)
            }
        }
        if !scheduleUsesCanonical, let canonical = cloudScheduleValue {
            let selectedByID = Dictionary(
                selectedSchedule.value.0.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for item in canonical.0 where !Self.classIsCleared(item) {
                if selectedByID[item.id].map(Self.classIsCleared) ?? true {
                    let id = item.id.uuidString
                    classTombstones.insert(id)
                    if classTombstoneBases[id] == nil {
                        classTombstoneBases[id] = Self.classContentFingerprint(item)
                    }
                }
            }
        }
        var eventTombstones = Self.eventTombstones(in: existingCloud)
        var eventTombstoneBases = Self.eventTombstoneBases(in: existingCloud)
        if !eventsUseCanonical {
            eventTombstones.subtract(selectedEvents.restoredEventIDs)
            for id in selectedEvents.restoredEventIDs {
                eventTombstoneBases.removeValue(forKey: id)
            }
        }
        if !eventsUseCanonical, let canonical = cloudEventsValue {
            let selectedIDs = Set(selectedEvents.value.map(\.id))
            for event in canonical where !selectedIDs.contains(event.id) {
                let id = event.id.uuidString
                eventTombstones.insert(id)
                if eventTombstoneBases[id] == nil {
                    eventTombstoneBases[id] = Self.eventContentFingerprint(event)
                }
            }
        }
        if !scheduleUsesCanonical {
            let sanitizedClasses = Self.applyingClassTombstones(
                selectedSchedule.value.0,
                classTombstones
            )
            migratedCloud["schedule"] = try encryption.encrypt(sanitizedClasses, userId: userId)
            migratedCloud["theme"] = try encryption.encrypt(selectedSchedule.value.1, userId: userId)
            migratedCloud["isSecondLunch"] = try encryption.encrypt(selectedSchedule.value.2, userId: userId)
            migratedCloud["scheduleUpdatedAt"] = Self.firestoreTimestamp(
                selectedSchedule.updatedAt
            )
            cloudNeedsWrite = true
        }
        if Self.classTombstones(in: migratedCloud) != classTombstones {
            migratedCloud["classTombstones"] = classTombstones.sorted()
            cloudNeedsWrite = true
        }
        if Self.classTombstoneBases(in: migratedCloud) != classTombstoneBases {
            migratedCloud["classTombstoneBases"] = classTombstoneBases
            cloudNeedsWrite = true
        }
        let scheduleInitialized = scheduleUsesCanonical
            ? canonicalScheduleIsAuthoritative
            : selectedLegacyScheduleCandidate?.carriesClasses == true
        if migratedCloud["scheduleInitialized"] as? Bool != scheduleInitialized {
            migratedCloud["scheduleInitialized"] = scheduleInitialized
            cloudNeedsWrite = true
        }
        let legacyEventsEstablishAuthority = bestLegacyEvents.map {
            !eventsUseCanonical || $0.updatedAt > cloudEventsTime
        } ?? false
        let eventsInitialized = (eventsUseCanonical && canonicalEventsAreAuthoritative)
            || legacyEventsEstablishAuthority
        if migratedCloud["eventsInitialized"] as? Bool != eventsInitialized {
            migratedCloud["eventsInitialized"] = eventsInitialized
            cloudNeedsWrite = true
        }
        if !eventsUseCanonical {
            let sanitizedEvents = selectedEvents.value.filter {
                !eventTombstones.contains($0.id.uuidString)
            }
            migratedCloud["events"] = try encryption.encrypt(sanitizedEvents, userId: userId)
            migratedCloud["eventsUpdatedAt"] = Self.firestoreTimestamp(selectedEvents.updatedAt)
            cloudNeedsWrite = true
        }
        if Self.eventTombstones(in: migratedCloud) != eventTombstones {
            migratedCloud["eventTombstones"] = eventTombstones.sorted()
            cloudNeedsWrite = true
        }
        if Self.eventTombstoneBases(in: migratedCloud) != eventTombstoneBases {
            migratedCloud["eventTombstoneBases"] = eventTombstoneBases
            cloudNeedsWrite = true
        }
        migratedCloud["schemaVersion"] = Self.cloudSchemaVersion

        if cloudNeedsWrite || needsReleasedMirror {
            try await writeMigratedCloudData(
                migratedCloud,
                initialCloud: initialCanonicalCloud ?? [:],
                initialRoot: userData,
                version4Recovery: userData["encrypted"] as? [String: Any],
                corruptVersion5Recovery: corruptVersion5Recovery,
                legacyRecovery: Self.legacyRecoveryFields(in: userData),
                seedReleasedMirror: needsReleasedMirror
                    || !scheduleUsesCanonical
                    || !eventsUseCanonical,
                for: userId
            )
        }

        if marker != Self.sessionMigrationVersion
            || syncMarker != Self.cloudSchemaVersion
            || rootSessionsNeedReconciliation {
            var sessions = migratableEmbeddedRootSessions
            sessions.append(contentsOf: Self.embeddedUsageSessions(in: oldStateData))
            sessions.append(contentsOf: usageSessions(from: oldSessionDocuments))
            var effectiveClear = Self.timestampOrNil(userData["usageSessionsClearedAt"])
            var sanitizedEmbeddedSessions = false
            if rootSessionsNeedReconciliation,
               (embeddedRootSessions.isEmpty
                    || Self.hasExplicitPre118UsageClear(in: userData)),
               let legacySessionUpdatedAt {
                let reconciledClear = max(
                    effectiveClear ?? .distantPast,
                    legacySessionUpdatedAt
                )
                effectiveClear = reconciledClear
                _ = try await db.runTransaction { transaction, errorPointer in
                    do {
                        let latest = try transaction.getDocument(userRef).data() ?? [:]
                        var usage = latest["usageStats"] as? [String: Any] ?? [:]
                        usage["sessions"] = []
                        var embedded = latest["sessions"] as? [String: Any] ?? [:]
                        embedded["records"] = []
                        transaction.setData([
                            "usageSessionsClearedAt": Timestamp(date: reconciledClear),
                            "usageStats": usage,
                            "sessions": embedded,
                            "usageSessionEmbeddedDigest": Self.usageSessionDigest([])
                        ], forDocument: userRef, merge: true)
                        transaction.updateData([
                            FieldPath(["usageStats.sessions"]): FieldValue.delete()
                        ] as [AnyHashable: Any], forDocument: userRef)
                        return true
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }
                sanitizedEmbeddedSessions = true
                try await deleteCanonicalSessions(
                    for: userId,
                    startingOnOrBefore: reconciledClear
                )
            }
            if let effectiveClear {
                sessions = sessions.filter {
                    Self.usageSessionStartedAt($0) > effectiveClear
                }
            }
            try await writeMigratedSessions(sessions, for: userId)
            var sessionState: [String: Any] = [
                "usageSessionMigrationVersion": Self.sessionMigrationVersion
            ]
            if hasEmbeddedRootSessionField {
                sessionState["usageSessionEmbeddedDigest"] = sanitizedEmbeddedSessions
                    ? Self.usageSessionDigest([])
                    : embeddedRootDigest
            }
            if let legacySessionUpdatedAt {
                sessionState["usageSessionLegacyUpdatedAt"] = Timestamp(
                    date: legacySessionUpdatedAt
                )
            }
            try await userRef.setData(sessionState, merge: true)
        }
        if syncMarker != Self.cloudSchemaVersion {
            guard let legacySyncSnapshot else {
                throw CloudDataSchemaError.concurrentMigrationChange
            }
            try await commitLegacySyncMigrationMarker(
                initial: legacySyncSnapshot,
                for: userId
            )
            // The root marker now makes every old-port session write fail at
            // the rules layer. Re-query once behind that fence so a session
            // that committed immediately before the marker cannot be skipped.
            let finalLegacySessions = try await legacyStateDocument(for: userId)
                .collection("sessions")
                .getDocuments()
                .documents
            try await writeMigratedSessions(
                usageSessions(from: finalLegacySessions),
                for: userId
            )
        }
        // Migration can rewrite canonical payloads, tombstones, released
        // mirrors, and marker fields. Cache the committed root rather than the
        // pre-migration read so the immediately following domain load cannot
        // decode stale state.
        Self.cacheValidatedRoot(
            try await userRef.getDocument().data() ?? [:],
            for: userId
        )
    }

    /// Atomically verifies every retained sync-domain source before fencing
    /// old porting clients. If any source changed after the migration read,
    /// the outer retry re-reads and re-applies it instead of marking stale
    /// canonical data complete.
    private func commitLegacySyncMigrationMarker(
        initial: LegacySyncSnapshot,
        for userId: String
    ) async throws {
        let userRef = userDocument(for: userId)
        let stateRef = legacyStateDocument(for: userId)
        let scheduleRef = legacyScheduleDocument(for: userId)
        let eventsRef = legacyEventsDocument(for: userId)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let latestState = try transaction.getDocument(stateRef).data()
                let latestSchedule = try transaction.getDocument(scheduleRef).data()
                let latestEvents = try transaction.getDocument(eventsRef).data()
                guard Self.optionalDocumentFingerprint(latestState)
                        == Self.optionalDocumentFingerprint(initial.state),
                      Self.optionalDocumentFingerprint(latestSchedule)
                        == Self.optionalDocumentFingerprint(initial.schedule),
                      Self.optionalDocumentFingerprint(latestEvents)
                        == Self.optionalDocumentFingerprint(initial.events) else {
                    throw CloudDataSchemaError.concurrentMigrationChange
                }
                transaction.setData([
                    "legacySyncMigrationVersion": Self.cloudSchemaVersion
                ], forDocument: userRef, merge: true)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    private func writeMigratedCloudData(
        _ candidate: [String: Any],
        initialCloud: [String: Any],
        initialRoot: [String: Any],
        version4Recovery: [String: Any]?,
        corruptVersion5Recovery: [String: Any]?,
        legacyRecovery: [String: Any],
        seedReleasedMirror: Bool,
        for userId: String
    ) async throws {
        let reference = userDocument(for: userId)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let latestRoot = try transaction.getDocument(reference).data() ?? [:]
                try Self.validateVersion5Container(in: latestRoot)
                if let futureVersion = Self.unsupportedTransitionalVersion(in: latestRoot) {
                    throw CloudDataSchemaError.unsupportedVersion(futureVersion)
                }
                let latestCloud = latestRoot[Self.cloudField] as? [String: Any] ?? [:]
                let latestVersion = Self.schemaVersion(in: latestCloud)
                guard latestVersion <= Self.cloudSchemaVersion else {
                    throw CloudDataSchemaError.unsupportedVersion(latestVersion)
                }
                if let version4Recovery {
                    guard let latestVersion4 = latestRoot["encrypted"] as? [String: Any],
                          Self.stableValue(latestVersion4) == Self.stableValue(version4Recovery) else {
                        throw CloudDataSchemaError.concurrentMigrationChange
                    }
                }
                guard Self.releasedScheduleFingerprint(latestRoot)
                        == Self.releasedScheduleFingerprint(initialRoot),
                      Self.releasedEventsFingerprint(latestRoot)
                        == Self.releasedEventsFingerprint(initialRoot),
                      Self.transitionalCloudFingerprint(latestRoot)
                        == Self.transitionalCloudFingerprint(initialRoot) else {
                    throw CloudDataSchemaError.concurrentMigrationChange
                }

                var mergedCloud = latestCloud
                let latestScheduleChanged = Self.cloudScheduleFingerprint(latestCloud)
                    != Self.cloudScheduleFingerprint(initialCloud)
                let latestEventsChanged = Self.cloudEventsFingerprint(latestCloud)
                    != Self.cloudEventsFingerprint(initialCloud)

                // Never replace a schema-5 field that appeared while this
                // migration was in flight merely because the concurrent map is
                // still partial. Retry from that exact partial payload so its
                // individually valid fields can participate in recovery.
                if latestScheduleChanged,
                   Self.hasAnyCloudScheduleField(latestCloud),
                   !Self.hasCloudScheduleFields(latestCloud) {
                    throw CloudDataSchemaError.concurrentMigrationChange
                }

                if !latestScheduleChanged || !Self.hasCloudScheduleFields(latestCloud) {
                    for key in [
                        "schedule", "theme", "isSecondLunch",
                        "scheduleUpdatedAt", "scheduleInitialized", "classTombstones",
                        "classTombstoneBases"
                    ] {
                        if let value = candidate[key] { mergedCloud[key] = value }
                    }
                }
                if !latestEventsChanged || latestCloud["events"] == nil {
                    for key in [
                        "events", "eventsUpdatedAt", "eventsInitialized", "eventTombstones",
                        "eventTombstoneBases"
                    ] {
                        if let value = candidate[key] { mergedCloud[key] = value }
                    }
                }
                for (key, value) in candidate where mergedCloud[key] == nil {
                    // A concurrent schema-5 event writer from before the
                    // presence flag existed is authoritative by compatibility.
                    // Do not attach this migration attempt's synthesized-false
                    // marker to that writer's newer payload.
                    if key == "eventsInitialized", latestEventsChanged { continue }
                    if key == "scheduleInitialized", latestScheduleChanged { continue }
                    mergedCloud[key] = value
                }
                mergedCloud["schemaVersion"] = Self.cloudSchemaVersion
                var rootWrite: [String: Any] = [
                    "uid": userId,
                    Self.cloudField: mergedCloud,
                    "scheduleInitialized": mergedCloud["scheduleInitialized"] as? Bool ?? true
                ]
                if let transitional = latestRoot[Self.transitionalCloudField]
                        as? [String: Any],
                   Self.schemaVersion(in: transitional) == Self.cloudSchemaVersion {
                    // Rules deliberately retain a released schema-5 carrier so
                    // a future-version value can never be deleted by an older
                    // client. Consolidate a known-v5 carrier to the exact map
                    // selected above; otherwise adding presence metadata to the
                    // canonical copy would leave two equal-time claimants and
                    // make the next read fail closed despite identical content.
                    rootWrite[Self.transitionalCloudField] = mergedCloud
                }
                // These are "latest source before rewrite" slots, not one-time
                // markers. A released/port build can recreate a v4 or legacy
                // carrier after an earlier migration. Keeping the first slot
                // forever can both strand the newer source (v4 rules require an
                // exact paired recovery) and archive the wrong bytes.
                if let version4Recovery {
                    rootWrite["migrationRecoveryV4"] = version4Recovery
                }
                if let corruptVersion5Recovery {
                    rootWrite["migrationRecoveryCorruptV5"] = corruptVersion5Recovery
                }
                if !legacyRecovery.isEmpty {
                    rootWrite["migrationRecoveryLegacy"] = legacyRecovery
                }
                if seedReleasedMirror || version4Recovery != nil {
                    // Seed a complete released-client mirror atomically. A
                    // partial mirror followed by `encrypted = true` makes old
                    // clients replace missing classes/lunch with defaults.
                    // A synthesized schedule is not authoritative. Released
                    // clients do not understand scheduleInitialized=false, so
                    // mirroring its defaults would make them erase real local
                    // classes on another device.
                    if mergedCloud["scheduleInitialized"] as? Bool != false {
                        rootWrite["encrypted"] = true
                        rootWrite["classes"] = mergedCloud["schedule"]
                        rootWrite["theme"] = mergedCloud["theme"]
                        rootWrite["isSecondLunch"] = mergedCloud["isSecondLunch"]
                        rootWrite["lastUpdated"] = mergedCloud["scheduleUpdatedAt"]
                            ?? FieldValue.serverTimestamp()
                    }
                    // A synthesized empty event domain is deliberately not
                    // mirrored to released clients: they cannot understand
                    // `eventsInitialized = false` and would treat that empty
                    // array as an instruction to erase established events.
                    if mergedCloud["eventsInitialized"] as? Bool != false {
                        rootWrite["eventsEncrypted"] = true
                        rootWrite["customEvents"] = mergedCloud["events"]
                        rootWrite["eventsUpdatedAt"] = mergedCloud["eventsUpdatedAt"]
                            ?? FieldValue.serverTimestamp()
                        rootWrite["eventsLastUpdated"] = mergedCloud["eventsUpdatedAt"]
                            ?? FieldValue.serverTimestamp()
                    }
                }
                transaction.setData(rootWrite, forDocument: reference, merge: true)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
    }

    // MARK: - Migration/session helpers

    private struct Attempt<Value> {
        let value: Value?
        let error: Error?
    }

    private func tryResult<Value>(_ operation: () throws -> Value) -> Attempt<Value> {
        do { return Attempt(value: try operation(), error: nil) }
        catch { return Attempt(value: nil, error: error) }
    }

    private func tryOptionalResult<Value>(_ operation: () throws -> Value?) -> Attempt<Value> {
        do { return Attempt(value: try operation(), error: nil) }
        catch { return Attempt(value: nil, error: error) }
    }

    nonisolated private static func normalizedUsageSessions(
        _ sessions: [[String: Any]]
    ) -> [[String: Any]] {
        var normalized: [[String: Any]] = []
        var indexes: [String: Int] = [:]

        for raw in sessions {
            let session = Self.normalizedUsageSession(raw)
            guard let id = session["id"] as? String else { continue }
            if let index = indexes[id] {
                if Self.usageSessionEndedAt(normalized[index]) < Self.usageSessionEndedAt(session) {
                    normalized[index] = session
                }
            } else {
                indexes[id] = normalized.count
                normalized.append(session)
            }
        }
        return normalized
    }

    nonisolated private static func normalizedUsageSession(
        _ session: [String: Any]
    ) -> [String: Any] {
        if let number = session["schemaVersion"] as? NSNumber,
           number.doubleValue.isFinite,
           number.doubleValue.rounded(.towardZero) == number.doubleValue,
           number.doubleValue > Double(usageSessionSchemaVersion) {
            // Unknown future records are recovery input, not data this build is
            // allowed to normalize. The migration writer below leaves them in
            // their existing carrier instead of silently changing v3+ to v2.
            return session
        }
        var normalized = session
        normalized["schemaVersion"] = usageSessionSchemaVersion
        normalized.removeValue(forKey: "duration")
        normalized.removeValue(forKey: "itemBreakdown")

        if normalized["featureViewCounts"] == nil,
           let legacyCounts = normalized["featureCounts"] {
            normalized["featureViewCounts"] = legacyCounts
        }
        normalized.removeValue(forKey: "featureCounts")

        if let legacyTabs = normalized["newsTabBreakdown"] as? [String: Any] {
            if normalized["newsTabDurations"] == nil {
                normalized["newsTabDurations"] = legacyTabs.mapValues {
                    ($0 as? [String: Any])?["duration"] ?? 0
                }
            }
            if normalized["newsTabViewCounts"] == nil {
                normalized["newsTabViewCounts"] = legacyTabs.mapValues {
                    ($0 as? [String: Any])?["viewCount"] ?? 0
                }
            }
        }
        normalized.removeValue(forKey: "newsTabBreakdown")

        if (normalized["id"] as? String)?.isEmpty != false {
            // Pre-1.18 builds had no ID and could persist more than one
            // snapshot of the same active session. The start time is the
            // stable logical identity; mutable duration/count fields must not
            // create extra documents for each snapshot.
            var identity: [String: Any]
            if let startedAt = normalized["startedAt"] {
                identity = ["startedAt": startedAt]
                if let appVersion = normalized["appVersion"] {
                    identity["appVersion"] = appVersion
                }
            } else {
                identity = normalized
                identity.removeValue(forKey: "id")
                identity.removeValue(forKey: "schemaVersion")
            }
            let digest = SHA256.hash(data: Data(Self.stableValue(identity).utf8))
            normalized["id"] = "legacy-" + digest.map { String(format: "%02x", $0) }.joined()
        }
        return normalized
    }

    nonisolated private static func exactUsageSessionSchemaVersion(
        in session: [String: Any]
    ) throws -> Int? {
        guard let raw = session["schemaVersion"] else { return nil }
        guard let number = raw as? NSNumber else {
            throw CloudDataSchemaError.corruptPayload("usage session schema")
        }
        let numericVersion = number.doubleValue
        guard numericVersion.isFinite,
              numericVersion.rounded(.towardZero) == numericVersion,
              numericVersion >= 0,
              numericVersion <= Double(Int.max) else {
            throw CloudDataSchemaError.corruptPayload("usage session schema")
        }
        return Int(numericVersion)
    }

    nonisolated private static func embeddedUsageSessions(in data: [String: Any]) -> [[String: Any]] {
        let records = (data["sessions"] as? [String: Any])?["records"] as? [[String: Any]] ?? []
        let nested = (data["usageStats"] as? [String: Any])?["sessions"] as? [[String: Any]] ?? []
        let dotted = data["usageStats.sessions"] as? [[String: Any]] ?? []
        return records + nested + dotted
    }

    nonisolated private static func embeddedUsageSessionsForMigration(
        in data: [String: Any]
    ) -> [[String: Any]] {
        let records = (data["sessions"] as? [String: Any])?["records"] as? [[String: Any]] ?? []
        let nested = (data["usageStats"] as? [String: Any])?["sessions"] as? [[String: Any]]
        let dotted = data["usageStats.sessions"] as? [[String: Any]] ?? []

        // Versions 1.16-1.17 appended to the literal dotted field, but their
        // Clear action wrote an empty nested array and could not remove that
        // literal field. An explicitly empty nested array is therefore a
        // durable clear signal: never resurrect the stale dotted snapshots as
        // canonical records. The raw field remains untouched for diagnosis.
        if nested?.isEmpty == true, !dotted.isEmpty {
            return records
        }
        return records + (nested ?? []) + dotted
    }

    nonisolated private static func hasExplicitPre118UsageClear(
        in data: [String: Any]
    ) -> Bool {
        guard let usage = data["usageStats"] as? [String: Any],
              let nested = usage["sessions"] as? [[String: Any]],
              nested.isEmpty,
              let dotted = data["usageStats.sessions"] as? [[String: Any]] else {
            return false
        }
        return !dotted.isEmpty
    }

    nonisolated private static func hasEmbeddedUsageSessionField(
        in data: [String: Any]
    ) -> Bool {
        ((data["sessions"] as? [String: Any])?["records"] != nil)
            || ((data["usageStats"] as? [String: Any])?["sessions"] != nil)
            || data["usageStats.sessions"] != nil
    }

    nonisolated private static func usageSessionDigest(_ sessions: [[String: Any]]) -> String {
        let stable = normalizedUsageSessions(sessions)
            .sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
            .map(Self.stableValue)
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(stable.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func usageSessions(from documents: [QueryDocumentSnapshot]) -> [[String: Any]] {
        documents.map { document in
            var data = document.data()
            // Apply the same content-derived identity used for embedded
            // pre-1.18 arrays so one logical session appearing in both source
            // shapes cannot migrate twice. Retain the source ID only as
            // recovery metadata.
            if data["id"] == nil { data["legacyDocumentID"] = document.documentID }
            return data
        }
    }

    nonisolated private static func stableValue(_ value: Any) -> String {
        if let timestamp = value as? Timestamp {
            return "timestamp:\(timestamp.seconds):\(timestamp.nanoseconds)"
        }
        if let date = value as? Date {
            return "date:\(date.timeIntervalSince1970)"
        }
        if value is NSNull { return "null" }
        if let string = value as? String { return "string:\(string)" }
        if let bool = value as? Bool { return "bool:\(bool)" }
        if let number = value as? NSNumber { return "number:\(number.stringValue)" }
        if let array = value as? [Any] {
            return "[" + array.map(Self.stableValue).joined(separator: ",") + "]"
        }
        if let dictionary = value as? [String: Any] {
            return "{" + dictionary.keys.sorted().map {
                "\($0):\(Self.stableValue(dictionary[$0]!))"
            }.joined(separator: ",") + "}"
        }
        return "other:\(String(describing: value))"
    }

    nonisolated private static func optionalDocumentFingerprint(
        _ data: [String: Any]?
    ) -> String {
        data.map(Self.stableValue) ?? "missing-document"
    }

    nonisolated private static func usageSessionEndedAt(_ session: [String: Any]) -> Date {
        if let timestamp = session["endedAt"] as? Timestamp { return timestamp.dateValue() }
        return session["endedAt"] as? Date ?? .distantPast
    }

    nonisolated private static func usageSessionStartedAt(_ session: [String: Any]) -> Date {
        if let timestamp = session["startedAt"] as? Timestamp { return timestamp.dateValue() }
        return session["startedAt"] as? Date ?? .distantPast
    }

    private func writeMigratedSessions(_ sessions: [[String: Any]], for userId: String) async throws {
        guard sessions.allSatisfy({ Self.timestampOrNil($0["startedAt"]) != nil }) else {
            throw CloudDataSchemaError.corruptPayload("usage sessions")
        }
        for session in sessions {
            _ = try Self.exactUsageSessionSchemaVersion(in: session)
        }
        let normalized = Self.normalizedUsageSessions(sessions)
        guard !normalized.isEmpty else { return }
        var index = 0
        while index < normalized.count {
            let chunk = Array(normalized[index..<min(index + 200, normalized.count)])
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let root = try transaction.getDocument(
                        self.userDocument(for: userId)
                    ).data() ?? [:]
                    let clearedAt = Self.timestampOrNil(root["usageSessionsClearedAt"])
                    var writes: [([String: Any], DocumentReference)] = []
                    // Firestore transactions retry if any document changes
                    // after these reads, closing the query-then-batch race with
                    // a newer background append on another device.
                    for session in chunk {
                        if let version = try Self.exactUsageSessionSchemaVersion(in: session),
                           version > Self.usageSessionSchemaVersion {
                            // Keep future embedded records in their retained
                            // source carrier for a compatible client to migrate.
                            continue
                        }
                        if let clearedAt,
                           Self.usageSessionStartedAt(session) <= clearedAt {
                            continue
                        }
                        guard let id = session["id"] as? String else { continue }
                        let reference = self.sessionsCollection(for: userId).document(id)
                        let existing = try transaction.getDocument(reference).data()
                        if let existing {
                            if let version = try Self.exactUsageSessionSchemaVersion(in: existing),
                               version > Self.usageSessionSchemaVersion {
                                continue
                            }
                            if Self.usageSessionEndedAt(existing)
                                >= Self.usageSessionEndedAt(session) {
                                continue
                            }
                        }
                        writes.append((session, reference))
                    }
                    for (session, reference) in writes {
                        transaction.setData(session, forDocument: reference, merge: true)
                    }
                    return writes.count
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            index += 200
        }
    }

    // MARK: - Schedule write helpers

    private func writeChangedScheduleFields(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        mayRestoreTombstones: Bool,
        for userId: String
    ) async throws {
        let previous = Self.snapshots[userId]
        let rewrites = Self.fieldsNeedingRewrite[userId] ?? []
        let needsCanonicalMigration = previous?.isCanonical != true
        let classesChanged = previous?.classes != classes
            || rewrites.contains(.classes)
            || needsCanonicalMigration
        let themeChanged = previous?.theme != theme
            || rewrites.contains(.theme)
            || needsCanonicalMigration
        let lunchChanged = previous?.isSecondLunch != isSecondLunch
            || rewrites.contains(.isSecondLunch)
            || needsCanonicalMigration
        guard classesChanged || themeChanged || lunchChanged else { return }

        var committed = (classes, theme, isSecondLunch)
        if let previous {
            let baseByID = Dictionary(
                previous.classes.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let localByID = Dictionary(
                classes.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let locallyDeletedClassIDs: Set<String> = Set(baseByID.compactMap { id, item in
                guard !Self.classIsCleared(item),
                      localByID[id].map(Self.classIsCleared) ?? true else { return nil }
                return id.uuidString
            })
            let explicitlyRestoredClassIDs: Set<String> = Set(localByID.compactMap { id, item in
                guard !Self.classIsCleared(item),
                      baseByID[id].map(Self.classIsCleared) ?? true else { return nil }
                return id.uuidString
            })
            let locallyEditedClassIDs: Set<String> = Set(localByID.compactMap { id, item in
                guard !Self.classIsCleared(item),
                      let base = baseByID[id],
                      !Self.classIsCleared(base),
                      item != base else { return nil }
                return id.uuidString
            })
            let reference = userDocument(for: userId)
            let result = try await db.runTransaction { [encryption] transaction, errorPointer in
                do {
                    let root = try transaction.getDocument(reference).data() ?? [:]
                    try Self.validateVersion5Container(in: root)
                    if let futureVersion = Self.unsupportedTransitionalVersion(in: root) {
                        throw CloudDataSchemaError.unsupportedVersion(futureVersion)
                    }
                    var cloud = Self.version5CloudData(in: root) ?? [:]
                    let storedVersion = Self.schemaVersion(in: cloud)
                    if storedVersion > Self.cloudSchemaVersion {
                        throw CloudDataSchemaError.unsupportedVersion(storedVersion)
                    }

                    var classTombstones = Self.classTombstones(in: cloud)
                    var classTombstoneBases = Self.classTombstoneBases(in: cloud)
                    classTombstones.formUnion(locallyDeletedClassIDs)
                    for id in locallyDeletedClassIDs where classTombstoneBases[id] == nil {
                        if let uuid = UUID(uuidString: id), let item = baseByID[uuid] {
                            classTombstoneBases[id] = Self.classContentFingerprint(item)
                        }
                    }
                    // An unchanged stale value must not undo another device's
                    // clear. A real offline edit is different from its loaded
                    // base, however, and preserving that edit is safer than
                    // silently discarding the user's new work.
                    if mayRestoreTombstones {
                        let restored = explicitlyRestoredClassIDs.union(locallyEditedClassIDs)
                        classTombstones.subtract(restored)
                        for id in restored { classTombstoneBases.removeValue(forKey: id) }
                    }
                    var remote = (
                        Self.applyingClassTombstones(previous.classes, classTombstones),
                        previous.theme,
                        previous.isSecondLunch
                    )
                    var canonicalRemoteClasses = remote.0
                    var canonicalTime = Date.distantPast
                    if Self.hasCloudScheduleFields(cloud) {
                        guard let scheduleBlob = cloud["schedule"] as? String,
                              let themeBlob = cloud["theme"] as? String,
                              let lunchBlob = cloud["isSecondLunch"] as? String else {
                            throw CloudDataSchemaError.corruptPayload("schedule")
                        }
                        remote = (
                            Self.applyingClassTombstones(try encryption.decrypt(
                                scheduleBlob,
                                as: [ClassItem].self,
                                userId: userId
                            ), classTombstones),
                            try encryption.decrypt(
                                themeBlob,
                                as: ThemeColors.self,
                                userId: userId
                            ),
                            try encryption.decrypt(
                                lunchBlob,
                                as: [Bool].self,
                                userId: userId
                            )
                        )
                        canonicalRemoteClasses = remote.0
                        canonicalTime = Self.timestamp(cloud["scheduleUpdatedAt"])
                    }

                    if root["encrypted"] as? Bool == true,
                       Self.legacyScheduleClaimed(in: root) {
                        var released = remote
                        if let value = root["classes"] {
                            guard let blob = value as? String else {
                                throw CloudDataSchemaError.corruptPayload("released schedule")
                            }
                            let decoded = try encryption.decrypt(
                                blob,
                                as: [ClassItem].self,
                                userId: userId
                            )
                            released.0 = Self.reconcilingLegacyClassIDs(
                                decoded,
                                with: canonicalRemoteClasses
                            )
                        }
                        if let value = root["theme"] {
                            guard let blob = value as? String else {
                                throw CloudDataSchemaError.corruptPayload("released theme")
                            }
                            released.1 = try encryption.decrypt(
                                blob,
                                as: ThemeColors.self,
                                userId: userId
                            )
                        }
                        if let value = root["isSecondLunch"] {
                            guard let blob = value as? String else {
                                throw CloudDataSchemaError.corruptPayload("released lunch")
                            }
                            released.2 = try encryption.decrypt(
                                blob,
                                as: [Bool].self,
                                userId: userId
                            )
                        }
                        let releasedTimestamp = Self.timestamp(root["lastUpdated"])
                        let resolved = Self.resolvingClassTombstones(
                            released.0,
                            tombstones: classTombstones,
                            bases: classTombstoneBases
                        )
                        var resolvedReleased = released
                        resolvedReleased.0 = resolved.value
                        if Self.canonicalScheduleIsAuthoritative(cloud),
                           !Self.scheduleValuesEqual(resolvedReleased, remote),
                           !Self.scheduleDifferenceIsVerifiedRestore(
                               ScheduleSource(
                                   value: resolvedReleased,
                                   updatedAt: releasedTimestamp,
                                   restoredClassIDs: resolved.restoredIDs
                               ),
                               ScheduleSource(value: remote, updatedAt: canonicalTime)
                           ),
                           Self.importedTimestampOrderingIsAmbiguous(
                               releasedTimestamp,
                               canonicalTime
                           ) {
                            throw CloudDataSchemaError.corruptPayload(
                                "ambiguous future schedule timestamp"
                            )
                        }
                        if releasedTimestamp > canonicalTime {
                            classTombstones.subtract(resolved.restoredIDs)
                            for id in resolved.restoredIDs {
                                classTombstoneBases.removeValue(forKey: id)
                            }
                            released = resolvedReleased
                            let releasedByID = Dictionary(
                                released.0.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first }
                            )
                            for item in canonicalRemoteClasses where !Self.classIsCleared(item) {
                                if releasedByID[item.id].map(Self.classIsCleared) ?? true {
                                    let id = item.id.uuidString
                                    classTombstones.insert(id)
                                    if classTombstoneBases[id] == nil {
                                        classTombstoneBases[id] = Self.classContentFingerprint(item)
                                    }
                                }
                            }
                            released.0 = Self.applyingClassTombstones(
                                released.0,
                                classTombstones
                            )
                            remote = released
                        }
                    }

                    let mergedClasses = GlobalDataStore.mergeClasses(
                        base: Self.applyingClassTombstones(previous.classes, classTombstones),
                        local: Self.applyingClassTombstones(classes, classTombstones),
                        remote: remote.0
                    )
                    let mergedTheme = Self.threeWayValue(
                        base: previous.theme,
                        local: theme,
                        remote: remote.1
                    )
                    let mergedLunch = Self.threeWayValue(
                        base: previous.isSecondLunch,
                        local: isSecondLunch,
                        remote: remote.2
                    )
                    let scheduleBlob = try encryption.encrypt(mergedClasses, userId: userId)
                    let themeBlob = try encryption.encrypt(mergedTheme, userId: userId)
                    let lunchBlob = try encryption.encrypt(mergedLunch, userId: userId)
                    let committedBlob = try encryption.encrypt(
                        SchedulePayload(
                            classes: mergedClasses,
                            theme: mergedTheme,
                            isSecondLunch: mergedLunch
                        ),
                        userId: userId
                    )

                    cloud["schemaVersion"] = Self.cloudSchemaVersion
                    cloud["schedule"] = scheduleBlob
                    cloud["theme"] = themeBlob
                    cloud["isSecondLunch"] = lunchBlob
                    cloud["scheduleInitialized"] = true
                    cloud["classTombstones"] = classTombstones.sorted()
                    cloud["classTombstoneBases"] = classTombstoneBases
                    cloud["scheduleUpdatedAt"] = FieldValue.serverTimestamp()
                    transaction.setData([
                        "uid": userId,
                        Self.cloudField: cloud,
                        "encrypted": true,
                        "classes": scheduleBlob,
                        "theme": themeBlob,
                        "isSecondLunch": lunchBlob,
                        "scheduleInitialized": true,
                        "lastUpdated": FieldValue.serverTimestamp()
                    ], forDocument: reference, merge: true)
                    return committedBlob
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard let committedBlob = result as? String else {
                throw CloudDataSchemaError.corruptPayload("schedule transaction")
            }
            let payload = try encryption.decrypt(
                committedBlob,
                as: SchedulePayload.self,
                userId: userId
            )
            committed = (payload.classes, payload.theme, payload.isSecondLunch)
        } else {
            // GlobalDataStore never reaches this path before its initial load.
            // Keeping it as a normal set allows Firestore to queue an already
            // validated first-device save while temporarily offline.
            let root = try await userDocument(for: userId).getDocument().data() ?? [:]
            try Self.validateVersion5Container(in: root)
            if let futureVersion = Self.unsupportedTransitionalVersion(in: root) {
                throw CloudDataSchemaError.unsupportedVersion(futureVersion)
            }
            if let versioned = root[Self.cloudField] as? [String: Any] {
                let version = Self.schemaVersion(in: versioned)
                if version > Self.cloudSchemaVersion {
                    throw CloudDataSchemaError.unsupportedVersion(version)
                }
            }
            let scheduleBlob = try encryption.encrypt(classes, userId: userId)
            let themeBlob = try encryption.encrypt(theme, userId: userId)
            let lunchBlob = try encryption.encrypt(isSecondLunch, userId: userId)
            try await userDocument(for: userId).setData([
                "uid": userId,
                Self.cloudField: [
                    "schemaVersion": Self.cloudSchemaVersion,
                    "schedule": scheduleBlob,
                    "theme": themeBlob,
                    "isSecondLunch": lunchBlob,
                    "scheduleInitialized": true,
                    "scheduleUpdatedAt": FieldValue.serverTimestamp()
                ],
                "encrypted": true,
                "classes": scheduleBlob,
                "theme": themeBlob,
                "isSecondLunch": lunchBlob,
                "scheduleInitialized": true,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        }

        Self.snapshots[userId] = CloudSnapshot(
            classes: committed.0,
            theme: committed.1,
            isSecondLunch: committed.2,
            isEncrypted: true,
            isCanonical: true
        )
        Self.fieldsNeedingRewrite[userId] = nil
    }

    private func cacheSchedule(
        _ schedule: ([ClassItem], ThemeColors, [Bool]),
        for userId: String,
        canonical: Bool
    ) {
        Self.snapshots[userId] = CloudSnapshot(
            classes: schedule.0,
            theme: schedule.1,
            isSecondLunch: schedule.2,
            isEncrypted: true,
            isCanonical: canonical
        )
        if schedule.0.contains(where: \.needsIDMigration) {
            Self.fieldsNeedingRewrite[userId, default: []].insert(.classes)
        }
    }

    private func clearPendingSave(_ id: UUID, for userId: String) {
        guard Self.pendingSaves[userId]?.id == id else { return }
        Self.pendingSaves[userId] = nil
    }

    private func clearPendingMigration(_ id: UUID, for userId: String) {
        guard Self.pendingMigrations[userId]?.id == id else { return }
        Self.pendingMigrations[userId] = nil
    }

    // MARK: - Source decoding and arbitration

    private func validateUnambiguousScheduleOrdering(
        _ sources: [ScheduleSource]
    ) throws {
        guard sources.count > 1 else { return }
        for leftIndex in 0..<(sources.count - 1) {
            for rightIndex in (leftIndex + 1)..<sources.count {
                let left = sources[leftIndex]
                let right = sources[rightIndex]
                if !Self.scheduleValuesEqual(left.value, right.value),
                   !Self.scheduleDifferenceIsVerifiedRestore(left, right),
                   Self.importedTimestampOrderingIsAmbiguous(
                       left.updatedAt,
                       right.updatedAt
                   ) {
                    throw CloudDataSchemaError.corruptPayload(
                        "ambiguous future schedule timestamp"
                    )
                }
            }
        }
    }

    private func validateUnambiguousEventOrdering(
        _ sources: [EventSource]
    ) throws {
        guard sources.count > 1 else { return }
        for leftIndex in 0..<(sources.count - 1) {
            for rightIndex in (leftIndex + 1)..<sources.count {
                let left = sources[leftIndex]
                let right = sources[rightIndex]
                if left.value != right.value,
                   !Self.eventDifferenceIsVerifiedRestore(left, right),
                   Self.importedTimestampOrderingIsAmbiguous(
                       left.updatedAt,
                       right.updatedAt
                   ) {
                    throw CloudDataSchemaError.corruptPayload(
                        "ambiguous future events timestamp"
                    )
                }
            }
        }
    }

    /// Tombstone base fingerprints provide stronger evidence than a device
    /// clock: an item whose content changed from the exact deleted base is an
    /// intentional restore. Ignore only those proven item differences while
    /// checking whether any other field still needs unsafe timestamp ordering.
    nonisolated private static func scheduleDifferenceIsVerifiedRestore(
        _ lhs: ScheduleSource,
        _ rhs: ScheduleSource
    ) -> Bool {
        let restoredIDs = lhs.restoredClassIDs.union(rhs.restoredClassIDs)
        guard !restoredIDs.isEmpty,
              lhs.value.1 == rhs.value.1,
              lhs.value.2 == rhs.value.2 else { return false }
        return lhs.value.0.filter { !restoredIDs.contains($0.id.uuidString) }
            == rhs.value.0.filter { !restoredIDs.contains($0.id.uuidString) }
    }

    nonisolated private static func eventDifferenceIsVerifiedRestore(
        _ lhs: EventSource,
        _ rhs: EventSource
    ) -> Bool {
        let restoredIDs = lhs.restoredEventIDs.union(rhs.restoredEventIDs)
        return eventValuesDifferOnlyByVerifiedRestorations(
            lhs.value,
            rhs.value,
            restoredIDs: restoredIDs
        )
    }

    nonisolated static func eventValuesDifferOnlyByVerifiedRestorations(
        _ lhs: [CustomEvent],
        _ rhs: [CustomEvent],
        restoredIDs: Set<String>
    ) -> Bool {
        guard !restoredIDs.isEmpty else { return false }
        return lhs.filter { !restoredIDs.contains($0.id.uuidString) }
            == rhs.filter { !restoredIDs.contains($0.id.uuidString) }
    }

    private func releasedMirrorNeedsTombstoneSanitization(
        root: [String: Any],
        cloud: [String: Any],
        userId: String
    ) -> Bool {
        let classTombstones = Self.classTombstones(in: cloud)
        if root["encrypted"] as? Bool == true,
           Self.legacyScheduleClaimed(in: root) {
            guard let raw = try? decodeLegacySchedule(root, userId: userId).0 else {
                // A released mirror can be complete by Firestore type while
                // containing truncated/wrong-key ciphertext. If canonical is
                // healthy, migration must repair that mirror so old builds are
                // not permanently stranded on unreadable data.
                return true
            }
            if !classTombstones.isEmpty {
                let canonicalClasses = (try? decodeCanonicalSchedule(
                    cloud,
                    userId: userId
                ).0) ?? []
                let reconciled = Self.reconcilingLegacyClassIDs(
                    raw,
                    with: canonicalClasses
                )
                if reconciled != raw
                    || Self.applyingClassTombstones(reconciled, classTombstones) != reconciled {
                    return true
                }
            }
        }

        let eventTombstones = Self.eventTombstones(in: cloud)
        if root["customEvents"] != nil {
            let raw: [CustomEvent]
            if root["eventsEncrypted"] as? Bool == true {
                guard let blob = root["customEvents"] as? String,
                      let decoded = try? encryption.decrypt(
                        blob,
                        as: [CustomEvent].self,
                        userId: userId
                      ) else { return true }
                raw = decoded
            } else {
                guard let dictionaries = root["customEvents"] as? [[String: Any]] else {
                    return true
                }
                guard let decoded = try? Self.decodePlaintextEvents(dictionaries) else {
                    return true
                }
                raw = decoded
            }
            if !eventTombstones.isEmpty,
               raw.contains(where: { eventTombstones.contains($0.id.uuidString) }) {
                return true
            }
        }
        return false
    }

    private func effectiveSchedule(in data: [String: Any], userId: String) throws -> ScheduleSource {
        try Self.validateVersion5Container(in: data)
        if let futureVersion = Self.unsupportedTransitionalVersion(in: data) {
            throw CloudDataSchemaError.unsupportedVersion(futureVersion)
        }
        if let cloud = Self.version5CloudData(in: data) {
            let version = Self.schemaVersion(in: cloud)
            if version > Self.cloudSchemaVersion {
                throw CloudDataSchemaError.unsupportedVersion(version)
            }
            guard version == Self.cloudSchemaVersion else {
                throw CloudDataSchemaError.corruptPayload("schema")
            }
            let canonical = try decodeCanonicalSchedule(cloud, userId: userId)
            let canonicalTime = Self.timestamp(cloud["scheduleUpdatedAt"])
            if let legacy = try legacyScheduleSource(
                in: data,
                userId: userId,
                fillingMissingFrom: canonical
            ) {
                let valuesDiffer = !Self.scheduleValuesEqual(legacy.value, canonical)
                if valuesDiffer,
                   Self.canonicalScheduleIsAuthoritative(cloud),
                   !Self.scheduleDifferenceIsVerifiedRestore(
                       legacy,
                       ScheduleSource(value: canonical, updatedAt: canonicalTime)
                   ),
                   Self.importedTimestampOrderingIsAmbiguous(
                       legacy.updatedAt,
                       canonicalTime
                   ) {
                    throw CloudDataSchemaError.corruptPayload(
                        "ambiguous future schedule timestamp"
                    )
                }
                if legacy.updatedAt > canonicalTime, valuesDiffer {
                    return legacy
                }
            }
            return ScheduleSource(value: canonical, updatedAt: canonicalTime)
        }
        if let legacy = try legacyScheduleSource(in: data, userId: userId) { return legacy }
        return ScheduleSource(value: ([], defaultTheme, [false, false]), updatedAt: .distantPast)
    }

    private func scheduleNeedsLegacyReconciliation(in data: [String: Any], userId: String) -> Bool {
        guard Self.unsupportedTransitionalVersion(in: data) == nil,
              let cloud = Self.version5CloudData(in: data),
              Self.schemaVersion(in: cloud) == Self.cloudSchemaVersion,
              let canonical = try? decodeCanonicalSchedule(cloud, userId: userId) else {
            return false
        }
        do {
            guard let legacy = try legacyScheduleSource(
                in: data,
                userId: userId,
                fillingMissingFrom: canonical
            ) else {
                return false
            }
            return legacy.updatedAt > Self.timestamp(cloud["scheduleUpdatedAt"])
                && !Self.scheduleValuesEqual(legacy.value, canonical)
        } catch {
            return false
        }
    }

    private func legacyScheduleSource(
        in data: [String: Any],
        userId: String,
        fillingMissingFrom baseline: ([ClassItem], ThemeColors, [Bool])? = nil
    ) throws -> ScheduleSource? {
        let cloud = Self.version5CloudData(in: data) ?? [:]
        let tombstones = Self.classTombstones(in: cloud)
        let tombstoneBases = Self.classTombstoneBases(in: cloud)
        if let encrypted = data["encrypted"] as? [String: Any],
           encrypted["schedule"] != nil {
            guard encrypted["schedule"] is String else {
                throw EncryptionError.invalidData
            }
            var value = try decodeCanonicalSchedule(
                encrypted,
                userId: userId,
                allowsCombinedVersion4Payload: true
            )
            let resolved = Self.resolvingClassTombstones(
                value.0,
                tombstones: tombstones,
                bases: tombstoneBases
            )
            value.0 = resolved.value
            return ScheduleSource(
                value: value,
                updatedAt: Self.timestamp(encrypted["scheduleUpdatedAt"]),
                restoredClassIDs: resolved.restoredIDs
            )
        }
        guard Self.legacyScheduleClaimed(in: data) else { return nil }
        var value = try decodeLegacySchedule(data, userId: userId)
        if let baseline {
            if data["classes"] == nil {
                value.0 = baseline.0
            } else {
                value.0 = Self.reconcilingLegacyClassIDs(value.0, with: baseline.0)
            }
            if data["theme"] == nil { value.1 = baseline.1 }
            if data["isSecondLunch"] == nil { value.2 = baseline.2 }
        }
        let resolved = Self.resolvingClassTombstones(
            value.0,
            tombstones: tombstones,
            bases: tombstoneBases
        )
        value.0 = resolved.value
        return ScheduleSource(
            value: value,
            updatedAt: Self.timestamp(data["lastUpdated"] ?? data["updatedAt"]),
            restoredClassIDs: resolved.restoredIDs
        )
    }

    private func legacyEventSource(in data: [String: Any], userId: String) throws -> EventSource? {
        let cloud = Self.version5CloudData(in: data) ?? [:]
        let tombstones = Self.eventTombstones(in: cloud)
        let tombstoneBases = Self.eventTombstoneBases(in: cloud)
        if let encrypted = data["encrypted"] as? [String: Any], encrypted["events"] != nil {
            let resolved = Self.resolvingEventTombstones(
                try decodeCanonicalEvents(encrypted, userId: userId),
                tombstones: tombstones,
                bases: tombstoneBases
            )
            return EventSource(
                value: resolved.value,
                updatedAt: Self.timestamp(encrypted["eventsUpdatedAt"]),
                restoredEventIDs: resolved.restoredIDs
            )
        }
        guard Self.legacyEventsClaimed(in: data) else { return nil }
        let events: [CustomEvent]
        if data["eventsEncrypted"] as? Bool == true {
            guard let blob = data["customEvents"] as? String else {
                throw EncryptionError.invalidData
            }
            events = try encryption.decrypt(blob, as: [CustomEvent].self, userId: userId)
        } else {
            guard let dictionaries = data["customEvents"] as? [[String: Any]] else {
                throw EncryptionError.invalidData
            }
            events = try Self.decodePlaintextEvents(dictionaries)
        }
        let resolved = Self.resolvingEventTombstones(
            events,
            tombstones: tombstones,
            bases: tombstoneBases
        )
        return EventSource(
            value: resolved.value,
            updatedAt: Self.legacyEventTimestamp(in: data),
            restoredEventIDs: resolved.restoredIDs
        )
    }

    private func encryptedScheduleDocumentSource(
        _ data: [String: Any]?,
        userId: String,
        reconcilingIDsWith baseline: [ClassItem]? = nil
    ) throws -> ScheduleSource? {
        guard let data, let blob = data["payload"] as? String else { return nil }
        let payload = try encryption.decrypt(blob, as: SchedulePayload.self, userId: userId)
        let classes = baseline.map {
            Self.reconcilingLegacyClassIDs(payload.classes, with: $0)
        } ?? payload.classes
        return ScheduleSource(
            value: (classes, payload.theme, payload.isSecondLunch),
            updatedAt: Self.timestamp(data["updatedAt"] ?? data["lastUpdated"])
        )
    }

    private func encryptedEventDocumentSource(
        _ data: [String: Any]?,
        userId: String
    ) throws -> EventSource? {
        guard let data, let blob = data["payload"] as? String else { return nil }
        return EventSource(
            value: try encryption.decrypt(blob, as: [CustomEvent].self, userId: userId),
            updatedAt: Self.timestamp(data["updatedAt"] ?? data["lastUpdated"])
        )
    }

    private func decodeCanonicalSchedule(
        _ cloud: [String: Any],
        userId: String,
        allowsCombinedVersion4Payload: Bool = false
    ) throws -> ([ClassItem], ThemeColors, [Bool]) {
        guard let schedule = cloud["schedule"] as? String else { throw EncryptionError.invalidData }
        if let theme = cloud["theme"] as? String,
           let lunch = cloud["isSecondLunch"] as? String {
            return (
                Self.applyingClassTombstones(
                    try encryption.decrypt(schedule, as: [ClassItem].self, userId: userId),
                    Self.classTombstones(in: cloud)
                ),
                try encryption.decrypt(theme, as: ThemeColors.self, userId: userId),
                try encryption.decrypt(lunch, as: [Bool].self, userId: userId)
            )
        }
        // Compatibility with the short-lived combined schema-4 schedule blob.
        guard allowsCombinedVersion4Payload else {
            throw EncryptionError.invalidData
        }
        let payload = try encryption.decrypt(schedule, as: SchedulePayload.self, userId: userId)
        return (
            Self.applyingClassTombstones(
                payload.classes,
                Self.classTombstones(in: cloud)
            ),
            payload.theme,
            payload.isSecondLunch
        )
    }

    private func decodeCanonicalEvents(_ cloud: [String: Any], userId: String) throws -> [CustomEvent] {
        guard let blob = cloud["events"] as? String else { throw EncryptionError.invalidData }
        let events = try encryption.decrypt(blob, as: [CustomEvent].self, userId: userId)
        let tombstones = Self.eventTombstones(in: cloud)
        return events.filter { !tombstones.contains($0.id.uuidString) }
    }

    private func decodeLegacySchedule(
        _ data: [String: Any],
        userId: String
    ) throws -> ([ClassItem], ThemeColors, [Bool]) {
        if data["encrypted"] as? Bool == true { return try loadEncrypted(data, userId: userId) }
        return try loadPlaintext(data)
    }

    private func loadEncrypted(
        _ data: [String: Any],
        userId: String
    ) throws -> ([ClassItem], ThemeColors, [Bool]) {
        var classes: [ClassItem] = []
        if let value = data["classes"] {
            guard let blob = value as? String else { throw EncryptionError.invalidData }
            classes = try encryption.decrypt(blob, as: [ClassItem].self, userId: userId)
        }
        var theme = defaultTheme
        if let value = data["theme"] {
            guard let blob = value as? String else { throw EncryptionError.invalidData }
            theme = try encryption.decrypt(blob, as: ThemeColors.self, userId: userId)
        }
        var lunches = [false, false]
        if let value = data["isSecondLunch"] {
            guard let blob = value as? String else { throw EncryptionError.invalidData }
            lunches = try encryption.decrypt(blob, as: [Bool].self, userId: userId)
        }
        return (classes, theme, lunches)
    }

    private func loadPlaintext(
        _ data: [String: Any]
    ) throws -> ([ClassItem], ThemeColors, [Bool]) {
        let classDictionaries: [[String: Any]]
        if let raw = data["classes"] {
            guard let dictionaries = raw as? [[String: Any]] else {
                throw EncryptionError.invalidData
            }
            classDictionaries = dictionaries
        } else {
            classDictionaries = []
        }
        let classes = try classDictionaries.map { dictionary in
            for key in ["id", "name", "teacher", "room"] {
                if let value = dictionary[key], !(value is String) {
                    throw EncryptionError.invalidData
                }
            }
            let persistedID = (dictionary["id"] as? String).flatMap(UUID.init(uuidString:))
            return ClassItem(
                id: persistedID ?? UUID(),
                name: dictionary["name"] as? String ?? "",
                teacher: dictionary["teacher"] as? String ?? "",
                room: dictionary["room"] as? String ?? "",
                needsIDMigration: persistedID == nil
            )
        }
        let themeDictionary: [String: Any]
        if let raw = data["theme"] {
            guard let dictionary = raw as? [String: Any] else {
                throw EncryptionError.invalidData
            }
            for key in ["primary", "secondary", "tertiary"] {
                if let value = dictionary[key], !(value is String) {
                    throw EncryptionError.invalidData
                }
            }
            themeDictionary = dictionary
        } else {
            themeDictionary = [:]
        }
        let theme = ThemeColors(
            primary: themeDictionary["primary"] as? String ?? "#00A5FFFF",
            secondary: themeDictionary["secondary"] as? String ?? "#00A5FF19",
            tertiary: themeDictionary["tertiary"] as? String ?? "#FFFFFFFF"
        )
        let lunches: [Bool]
        if let stored = data["isSecondLunch"] as? [Bool] {
            lunches = stored
        } else if let stored = data["isSecondLunch"] as? [NSNumber] {
            lunches = stored.map(\.boolValue)
        } else if data["isSecondLunch"] != nil {
            throw EncryptionError.invalidData
        } else {
            lunches = [false, false]
        }
        return (classes, theme, lunches)
    }

    private static func decodePlaintextEvents(
        _ dictionaries: [[String: Any]]
    ) throws -> [CustomEvent] {
        let events = dictionaries.compactMap(CloudEventsDataManager.eventFromDict)
        guard events.count == dictionaries.count else { throw EncryptionError.invalidData }
        return events
    }

    // MARK: - Firestore references and deletion helpers

    private var defaultTheme: ThemeColors {
        ThemeColors(primary: "#00A5FFFF", secondary: "#00A5FF19", tertiary: "#FFFFFFFF")
    }

    private func userDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId)
    }

    private func accountDeletionRequestDocument(for userId: String) -> DocumentReference {
        db.collection("accountDeletionRequests").document(userId)
    }

    private func legacyStateDocument(for userId: String) -> DocumentReference {
        userDocument(for: userId).collection("sync").document("state")
    }

    private func legacyScheduleDocument(for userId: String) -> DocumentReference {
        userDocument(for: userId).collection("sync").document("schedule")
    }

    private func legacyEventsDocument(for userId: String) -> DocumentReference {
        userDocument(for: userId).collection("sync").document("events")
    }

    private func sessionsCollection(for userId: String) -> CollectionReference {
        userDocument(for: userId).collection("sessions")
    }

    private func deleteCanonicalSessions(
        for userId: String,
        startingOnOrBefore date: Date
    ) async throws {
        let documents = try await sessionsCollection(for: userId).getDocuments().documents
        try await deleteSessionReferences(
            documents.map(\.reference),
            ifStartingOnOrBefore: date
        )
    }

    private func deleteSessions(
        in collection: CollectionReference,
        startingOnOrBefore date: Date
    ) async throws {
        let documents = try await collection.getDocuments().documents
        try await deleteSessionReferences(
            documents.map(\.reference),
            ifStartingOnOrBefore: date
        )
    }

    private func deleteSessionReferences(
        _ references: [DocumentReference],
        ifStartingOnOrBefore date: Date
    ) async throws {
        var index = 0
        while index < references.count {
            let chunk = Array(references[index..<min(index + 200, references.count)])
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    var deletions: [DocumentReference] = []
                    for reference in chunk {
                        let snapshot = try transaction.getDocument(reference)
                        if snapshot.exists,
                           Self.usageSessionStartedAt(snapshot.data() ?? [:]) <= date {
                            deletions.append(reference)
                        }
                    }
                    for reference in deletions {
                        transaction.deleteDocument(reference)
                    }
                    return deletions.count
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            index += 200
        }
    }

    // MARK: - Pure helpers retained for regression tests

    nonisolated static func isCanonicalUserDocument(_ data: [String: Any]) -> Bool {
        if let cloud = version5CloudData(in: data),
           schemaVersion(in: cloud) == cloudSchemaVersion {
            return hasCloudScheduleFields(cloud) && cloud["events"] is String
        }
        // Recognize the old complete v4 shape for migration-focused tests.
        guard let encrypted = data["encrypted"] as? [String: Any] else { return false }
        return schemaVersion(in: encrypted) == 4
            && hasCloudScheduleFields(encrypted)
            && encrypted["events"] is String
    }

    nonisolated static func migrationWriteData(
        candidate: [String: Any],
        latestRoot: [String: Any]
    ) -> [String: Any] {
        var result = candidate
        for (key, value) in latestRoot { result[key] = value }
        var encrypted = candidate["encrypted"] as? [String: Any] ?? [:]
        if let latest = latestRoot["encrypted"] as? [String: Any] {
            for (key, value) in latest where key != "schemaVersion" {
                encrypted[key] = value
            }
            let latestVersion = schemaVersion(in: latest)
            if latestVersion > 4 { encrypted["schemaVersion"] = latestVersion }
        }
        result["encrypted"] = encrypted
        return result
    }

    nonisolated static func fillingMissingEncryptedFields(
        existing: [String: Any],
        fallback: [String: Any]
    ) -> [String: Any] {
        var result = existing
        for (key, value) in fallback where result[key] == nil { result[key] = value }
        return result
    }

    nonisolated static func mergedLegacyUserData(
        oldState: [String: Any],
        userRoot: [String: Any]
    ) -> [String: Any] {
        var merged = oldState
        merged.merge(userRoot) { _, root in root }
        return merged
    }

    nonisolated private static func threeWayValue<Value: Equatable>(
        base: Value,
        local: Value,
        remote: Value
    ) -> Value {
        if local == base { return remote }
        if remote == base { return local }
        if local == remote { return local }
        return local
    }

    static func assertCloudWriteAllowed(for userId: String) throws {
        try assertUserIsNotBeingDeleted(userId)
        if let error = cloudWriteBlocks[userId] { throw error }
    }

    static func recentValidatedRootData(for userId: String) -> [String: Any]? {
        guard let cached = validatedRoots[userId],
              Date().timeIntervalSince(cached.cachedAt) < 2 else {
            validatedRoots[userId] = nil
            return nil
        }
        return cached.data
    }

    static func cacheValidatedRoot(_ data: [String: Any], for userId: String) {
        validatedRoots[userId] = CachedRoot(data: data, cachedAt: Date())
    }

    /// Removes every decoded schedule/root cache after Firestore confirms the
    /// user root does not exist. The returned state is deliberately
    /// non-authoritative: a missing root is not the same as a versioned,
    /// encrypted empty schedule, so first-sync local data must be preserved.
    static func scheduleStateForMissingRoot(
        for userId: String
    ) -> ([ClassItem], ThemeColors, [Bool], Bool) {
        snapshots[userId] = nil
        fieldsNeedingRewrite[userId] = nil
        validatedRoots[userId] = nil
        return ([], .defaultTheme, [false, false], false)
    }

    static func clearValidatedRootCache(for userId: String) {
        validatedRoots[userId] = nil
    }

    private static func taskCompletes(
        _ task: Task<Void, Error>,
        within timeout: Duration
    ) async -> Bool {
        let outcomes = AsyncStream<Bool> { continuation in
            Task { @MainActor in
                _ = try? await task.value
                continuation.yield(true)
                continuation.finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                continuation.yield(false)
                continuation.finish()
            }
        }
        for await completed in outcomes { return completed }
        return false
    }

    private static func assertUserIsNotBeingDeleted(_ userId: String) throws {
        if deletingUsers.contains(userId) {
            throw CloudDataDeletionError.deletionInProgress
        }
    }

    static func noteCloudReadFailure(_ error: Error, for userId: String) {
        if let schemaError = error as? CloudDataSchemaError {
            cloudWriteBlocks[userId] = schemaError
        } else if error is EncryptionError {
            cloudWriteBlocks[userId] = .corruptPayload("payload")
        }
    }

    nonisolated static func isFirestoreUnavailable(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.unavailable.rawValue
    }

    nonisolated private static func schemaVersion(in data: [String: Any]) -> Int {
        (data["schemaVersion"] as? NSNumber)?.intValue ?? 0
    }

    /// `cloudDataV5` is an atomic, versioned container. Treating a malformed
    /// value as if the field were absent would let migration or a direct save
    /// replace the only canonical copy with defaults. Fail closed and retain
    /// the original bytes for recovery instead.
    nonisolated private static func validateVersion5Container(
        in root: [String: Any]
    ) throws {
        if let raw = root[cloudField] {
            guard let cloud = raw as? [String: Any] else {
                throw CloudDataSchemaError.corruptPayload("schema")
            }
            let version = try exactSchemaVersion(in: cloud)
            if version > cloudSchemaVersion {
                throw CloudDataSchemaError.unsupportedVersion(version)
            }
            guard version == cloudSchemaVersion else {
                throw CloudDataSchemaError.corruptPayload("schema")
            }
            try validateCloudMetadata(in: cloud)
        }
        if let raw = root[transitionalCloudField] {
            guard let transitional = raw as? [String: Any] else {
                throw CloudDataSchemaError.corruptPayload("schema")
            }
            let version = try exactSchemaVersion(in: transitional)
            if version > cloudSchemaVersion {
                throw CloudDataSchemaError.unsupportedVersion(version)
            }
            guard version == cloudSchemaVersion else {
                throw CloudDataSchemaError.corruptPayload("schema")
            }
            try validateCloudMetadata(in: transitional)
        }
        if let raw = root["encrypted"] {
            if !(raw is Bool) {
                guard let version4 = raw as? [String: Any] else {
                    throw CloudDataSchemaError.corruptPayload("schema")
                }
                let version = try exactSchemaVersion(in: version4)
                if version > 4 {
                    throw CloudDataSchemaError.unsupportedVersion(version)
                }
                guard version == 4 else {
                    throw CloudDataSchemaError.corruptPayload("schema")
                }
            }
        }
        if let initialized = root["scheduleInitialized"], !(initialized is Bool) {
            throw CloudDataSchemaError.corruptPayload("schedule metadata")
        }
        _ = try migrationMarker(in: root, key: "usageSessionMigrationVersion")
        _ = try migrationMarker(in: root, key: "legacySyncMigrationVersion")
        try validateEmbeddedUsageCarriers(in: root)
        // The short-lived port wrote schema 5 to `cloudData`; released builds
        // write `cloudDataV5`. If both survived a partial rollout, silently
        // preferring one whole map can discard the newer schedule or events
        // domain. Reconcile by per-domain timestamps, and fail closed when two
        // different payloads claim the exact same ordering token.
        _ = try reconciledVersion5CloudData(in: root)
    }

    nonisolated static func validatedVersion5CloudData(
        in root: [String: Any]
    ) throws -> [String: Any]? {
        try validateVersion5Container(in: root)
        return try reconciledVersion5CloudData(in: root)
    }

    nonisolated private static func exactSchemaVersion(
        in data: [String: Any]
    ) throws -> Int {
        guard let number = data["schemaVersion"] as? NSNumber else {
            throw CloudDataSchemaError.corruptPayload("schema")
        }
        let numericVersion = number.doubleValue
        guard numericVersion.isFinite,
              numericVersion.rounded(.towardZero) == numericVersion,
              numericVersion >= Double(Int.min),
              numericVersion <= Double(Int.max) else {
            throw CloudDataSchemaError.corruptPayload("schema")
        }
        return Int(numericVersion)
    }

    nonisolated private static func migrationMarker(
        in data: [String: Any],
        key: String
    ) throws -> Int? {
        guard let raw = data[key] else { return nil }
        guard let number = raw as? NSNumber else {
            throw CloudDataSchemaError.corruptPayload("migration marker")
        }
        let numericVersion = number.doubleValue
        guard numericVersion.isFinite,
              numericVersion.rounded(.towardZero) == numericVersion,
              numericVersion >= 0,
              numericVersion <= Double(Int.max) else {
            throw CloudDataSchemaError.corruptPayload("migration marker")
        }
        let version = Int(numericVersion)
        if version > cloudSchemaVersion {
            throw CloudDataSchemaError.unsupportedVersion(version)
        }
        return version
    }

    /// Wrong-typed embedded usage carriers must not be interpreted as an empty
    /// array. Doing so would turn a corrupt port into a Clear operation and
    /// delete valid canonical session documents.
    nonisolated private static func validateEmbeddedUsageCarriers(
        in data: [String: Any]
    ) throws {
        if let raw = data["usageStats"] {
            guard let usage = raw as? [String: Any] else {
                throw CloudDataSchemaError.corruptPayload("usage sessions")
            }
            if let sessions = usage["sessions"], !(sessions is [[String: Any]]) {
                throw CloudDataSchemaError.corruptPayload("usage sessions")
            }
        }
        if let sessions = data["usageStats.sessions"],
           !(sessions is [[String: Any]]) {
            throw CloudDataSchemaError.corruptPayload("usage sessions")
        }
        if let raw = data["sessions"] {
            guard let sessions = raw as? [String: Any] else {
                throw CloudDataSchemaError.corruptPayload("usage sessions")
            }
            if let records = sessions["records"], !(records is [[String: Any]]) {
                throw CloudDataSchemaError.corruptPayload("usage sessions")
            }
        }
        for key in [
            "usageStatsUpdatedAt",
            "usageSessionsClearedAt",
            "usageSessionLegacyUpdatedAt"
        ] {
            if let value = data[key], !(value is Timestamp), !(value is Date) {
                throw CloudDataSchemaError.corruptPayload("usage timestamp")
            }
        }
    }

    nonisolated private static func validateCloudMetadata(
        in cloud: [String: Any]
    ) throws {
        if let tombstones = cloud["classTombstones"],
           !(tombstones is [String]) {
            throw CloudDataSchemaError.corruptPayload("class tombstones")
        }
        if let tombstones = cloud["eventTombstones"],
           !(tombstones is [String]) {
            throw CloudDataSchemaError.corruptPayload("event tombstones")
        }
        for key in ["classTombstoneBases", "eventTombstoneBases"] {
            if let raw = cloud[key] {
                guard let bases = raw as? [String: Any],
                      bases.values.allSatisfy({ $0 is String }) else {
                    throw CloudDataSchemaError.corruptPayload("tombstone bases")
                }
            }
        }
        if let initialized = cloud["scheduleInitialized"], !(initialized is Bool) {
            throw CloudDataSchemaError.corruptPayload("schedule metadata")
        }
        if let initialized = cloud["eventsInitialized"], !(initialized is Bool) {
            throw CloudDataSchemaError.corruptPayload("events metadata")
        }
        for key in ["scheduleUpdatedAt", "eventsUpdatedAt"] {
            if let value = cloud[key], !(value is Timestamp), !(value is Date) {
                throw CloudDataSchemaError.corruptPayload("timestamp metadata")
            }
        }
        if hasAnyCloudScheduleField(cloud), cloud["scheduleUpdatedAt"] == nil {
            throw CloudDataSchemaError.corruptPayload("schedule timestamp")
        }
        if cloud["events"] != nil, cloud["eventsUpdatedAt"] == nil {
            throw CloudDataSchemaError.corruptPayload("events timestamp")
        }
    }

    nonisolated private static func version5CloudData(
        in root: [String: Any]
    ) -> [String: Any]? {
        if let resolved = try? reconciledVersion5CloudData(in: root) {
            return resolved
        }
        // Critical read/write paths validate first and therefore never reach
        // this fallback for ambiguous data. Keep the pure regression helpers
        // nonthrowing while still refusing to reinterpret a non-v5 carrier.
        if let versioned = root[cloudField] as? [String: Any],
           schemaVersion(in: versioned) == cloudSchemaVersion {
            return versioned
        }
        guard let transitional = root[transitionalCloudField] as? [String: Any],
              schemaVersion(in: transitional) == cloudSchemaVersion else { return nil }
        return transitional
    }

    nonisolated private static func reconciledVersion5CloudData(
        in root: [String: Any]
    ) throws -> [String: Any]? {
        let canonical = root[cloudField] as? [String: Any]
        let transitional = root[transitionalCloudField] as? [String: Any]
        guard let canonical else { return transitional }
        guard let transitional else { return canonical }

        var resolved = canonical
        try reconcileVersion5Domain(
            canonical: canonical,
            transitional: transitional,
            keys: [
                "schedule", "theme", "isSecondLunch", "scheduleUpdatedAt",
                "scheduleInitialized", "classTombstones", "classTombstoneBases"
            ],
            timestampKey: "scheduleUpdatedAt",
            domain: "schedule",
            into: &resolved
        )
        try reconcileVersion5Domain(
            canonical: canonical,
            transitional: transitional,
            keys: [
                "events", "eventsUpdatedAt", "eventsInitialized",
                "eventTombstones", "eventTombstoneBases"
            ],
            timestampKey: "eventsUpdatedAt",
            domain: "events",
            into: &resolved
        )
        resolved["schemaVersion"] = cloudSchemaVersion
        return resolved
    }

    nonisolated private static func reconcileVersion5Domain(
        canonical: [String: Any],
        transitional: [String: Any],
        keys: [String],
        timestampKey: String,
        domain: String,
        into resolved: inout [String: Any]
    ) throws {
        let canonicalPresent = keys.contains { canonical[$0] != nil }
        let transitionalPresent = keys.contains { transitional[$0] != nil }
        guard transitionalPresent else { return }
        guard canonicalPresent else {
            replaceVersion5Domain(in: &resolved, with: transitional, keys: keys)
            return
        }

        let canonicalFingerprint = keys.map {
            canonical[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
        let transitionalFingerprint = keys.map {
            transitional[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
        guard canonicalFingerprint != transitionalFingerprint else { return }

        let canonicalTimestamp = timestamp(canonical[timestampKey])
        let transitionalTimestamp = timestamp(transitional[timestampKey])
        let valueKeys = keys.filter { $0 != timestampKey }
        let canonicalValueFingerprint = valueKeys.map {
            canonical[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
        let transitionalValueFingerprint = valueKeys.map {
            transitional[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
        if canonicalValueFingerprint != transitionalValueFingerprint,
           importedTimestampOrderingIsAmbiguous(
               canonicalTimestamp,
               transitionalTimestamp
           ) {
            throw CloudDataSchemaError.corruptPayload("ambiguous future \(domain) schema")
        }
        if transitionalTimestamp > canonicalTimestamp {
            replaceVersion5Domain(in: &resolved, with: transitional, keys: keys)
        } else if canonicalTimestamp == transitionalTimestamp {
            throw CloudDataSchemaError.corruptPayload("ambiguous \(domain) schema")
        }
    }

    nonisolated private static func replaceVersion5Domain(
        in destination: inout [String: Any],
        with source: [String: Any],
        keys: [String]
    ) {
        for key in keys {
            if let value = source[key] {
                destination[key] = value
            } else {
                destination.removeValue(forKey: key)
            }
        }
    }

    nonisolated private static func unsupportedTransitionalVersion(
        in root: [String: Any]
    ) -> Int? {
        guard let transitional = root[transitionalCloudField] as? [String: Any] else {
            return nil
        }
        let version = schemaVersion(in: transitional)
        return version > cloudSchemaVersion ? version : nil
    }

    nonisolated private static func hasCloudScheduleFields(_ cloud: [String: Any]) -> Bool {
        cloud["schedule"] is String
            && cloud["theme"] is String
            && cloud["isSecondLunch"] is String
    }

    nonisolated private static func hasAnyCloudScheduleField(
        _ cloud: [String: Any]
    ) -> Bool {
        cloud["schedule"] != nil
            || cloud["theme"] != nil
            || cloud["isSecondLunch"] != nil
    }

    nonisolated private static func eventTombstones(in cloud: [String: Any]) -> Set<String> {
        Set(cloud["eventTombstones"] as? [String] ?? [])
    }

    nonisolated static func eventTombstoneBases(
        in cloud: [String: Any]
    ) -> [String: String] {
        guard let raw = cloud["eventTombstoneBases"] as? [String: Any] else { return [:] }
        return raw.reduce(into: [:]) { result, entry in
            if let value = entry.value as? String { result[entry.key] = value }
        }
    }

    nonisolated private static func classTombstones(in cloud: [String: Any]) -> Set<String> {
        Set(cloud["classTombstones"] as? [String] ?? [])
    }

    nonisolated private static func classTombstoneBases(
        in cloud: [String: Any]
    ) -> [String: String] {
        guard let raw = cloud["classTombstoneBases"] as? [String: Any] else { return [:] }
        return raw.reduce(into: [:]) { result, entry in
            if let value = entry.value as? String { result[entry.key] = value }
        }
    }

    nonisolated private static func classContentFingerprint(_ item: ClassItem) -> String {
        sha256(stableValue([
            "name": item.name,
            "teacher": item.teacher,
            "room": item.room
        ]))
    }

    nonisolated static func eventContentFingerprint(_ event: CustomEvent) -> String {
        sha256(stableValue([
            "title": event.title,
            "startTime": ["h": event.startTime.h, "m": event.startTime.m, "s": event.startTime.s],
            "endTime": ["h": event.endTime.h, "m": event.endTime.m, "s": event.endTime.s],
            "location": event.location,
            "note": event.note,
            "color": event.color,
            "repeatPattern": event.repeatPattern.rawValue,
            "kind": event.kind.rawValue,
            "reminderOffsets": event.reminderOffsets.map(\.rawValue),
            "applicableDays": event.applicableDays.sorted()
        ]))
    }

    nonisolated private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated private static func classIsCleared(_ item: ClassItem) -> Bool {
        item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated private static func applyingClassTombstones(
        _ classes: [ClassItem],
        _ tombstones: Set<String>
    ) -> [ClassItem] {
        classes.map { item in
            guard tombstones.contains(item.id.uuidString) else { return item }
            return ClassItem(id: item.id, name: "", teacher: "", room: "")
        }
    }

    nonisolated private static func resolvingClassTombstones(
        _ classes: [ClassItem],
        tombstones: Set<String>,
        bases: [String: String]
    ) -> (value: [ClassItem], restoredIDs: Set<String>) {
        var restoredIDs: Set<String> = []
        let value = classes.map { item in
            let id = item.id.uuidString
            guard tombstones.contains(id) else { return item }
            if let base = bases[id],
               !classIsCleared(item),
               classContentFingerprint(item) != base {
                restoredIDs.insert(id)
                return item
            }
            return ClassItem(id: item.id, name: "", teacher: "", room: "")
        }
        return (value, restoredIDs)
    }

    nonisolated static func resolvingEventTombstones(
        _ events: [CustomEvent],
        tombstones: Set<String>,
        bases: [String: String]
    ) -> (value: [CustomEvent], restoredIDs: Set<String>) {
        var restoredIDs: Set<String> = []
        let value = events.filter { event in
            let id = event.id.uuidString
            guard tombstones.contains(id) else { return true }
            if let base = bases[id], eventContentFingerprint(event) != base {
                restoredIDs.insert(id)
                return true
            }
            return false
        }
        return (value, restoredIDs)
    }

    /// Class UUIDs were added after Schedule 1.17. Older clients preserve the
    /// array order but strip those unknown UUID fields whenever they save. Map
    /// such records back to the canonical IDs by position before applying
    /// tombstones, otherwise each old-client save invents new identities and a
    /// later stale replay can resurrect a class the user explicitly cleared.
    nonisolated private static func reconcilingLegacyClassIDs(
        _ classes: [ClassItem],
        with baseline: [ClassItem]
    ) -> [ClassItem] {
        classes.enumerated().map { index, item in
            guard item.needsIDMigration, baseline.indices.contains(index) else {
                return item
            }
            return ClassItem(
                id: baseline[index].id,
                name: item.name,
                teacher: item.teacher,
                room: item.room
            )
        }
    }

    nonisolated private static func canonicalScheduleIsAuthoritative(
        _ cloud: [String: Any]
    ) -> Bool {
        guard hasCloudScheduleFields(cloud) else { return false }
        return cloud["scheduleInitialized"] as? Bool != false
    }

    nonisolated private static func canonicalEventsAreAuthoritative(
        _ cloud: [String: Any]
    ) -> Bool {
        guard cloud["events"] is String else { return false }
        // Missing defaults to true for schema-5 documents written before this
        // explicit domain-presence marker was introduced.
        return cloud["eventsInitialized"] as? Bool != false
    }

    nonisolated private static func scheduleIsAuthoritative(in root: [String: Any]) -> Bool {
        if let cloud = version5CloudData(in: root) {
            return canonicalScheduleIsAuthoritative(cloud)
        }
        if let version4 = root["encrypted"] as? [String: Any],
           hasCloudScheduleFields(version4) {
            return root["scheduleInitialized"] as? Bool != false
        }
        return legacyScheduleClaimed(in: root)
            && root["scheduleInitialized"] as? Bool != false
    }

    nonisolated private static func legacyScheduleClaimed(in data: [String: Any]) -> Bool {
        data["classes"] != nil
            || data["theme"] != nil
            || data["isSecondLunch"] != nil
            || (data["encrypted"] as? [String: Any])?["schedule"] != nil
    }

    nonisolated private static func legacyScheduleCarriesClasses(
        _ data: [String: Any]
    ) -> Bool {
        data["classes"] != nil
            || ((data["encrypted"] as? [String: Any])?["schedule"] is String)
    }

    nonisolated private static func legacyEventsClaimed(in data: [String: Any]) -> Bool {
        data["customEvents"] != nil
            || (data["encrypted"] as? [String: Any])?["events"] != nil
    }

    nonisolated private static func legacyScheduleCandidate(
        source: ScheduleSource,
        data: [String: Any]
    ) -> LegacyScheduleCandidate {
        if (data["encrypted"] as? [String: Any])?["schedule"] is String {
            return LegacyScheduleCandidate(
                source: source,
                carriesClasses: true,
                carriesTheme: true,
                carriesLunch: true
            )
        }
        return LegacyScheduleCandidate(
            source: source,
            carriesClasses: data["classes"] != nil,
            carriesTheme: data["theme"] != nil,
            carriesLunch: data["isSecondLunch"] != nil
        )
    }

    nonisolated private static func hasCompleteReleasedScheduleMirror(
        _ data: [String: Any]
    ) -> Bool {
        data["encrypted"] as? Bool == true
            && data["classes"] is String
            && data["theme"] is String
            && data["isSecondLunch"] is String
    }

    nonisolated private static func hasCompleteReleasedEventsMirror(
        _ data: [String: Any]
    ) -> Bool {
        data["eventsEncrypted"] as? Bool == true && data["customEvents"] is String
    }

    nonisolated private static func legacyRecoveryFields(
        in data: [String: Any]
    ) -> [String: Any] {
        let keys = [
            "encrypted", "classes", "theme", "isSecondLunch", "lastUpdated",
            "eventsEncrypted", "customEvents", "eventsLastUpdated", "eventsUpdatedAt"
        ]
        var recovery: [String: Any] = [:]
        for key in keys {
            if let value = data[key] { recovery[key] = value }
        }
        return recovery
    }

    nonisolated private static func timestamp(_ value: Any?) -> Date {
        timestampOrNil(value) ?? .distantPast
    }

    nonisolated private static func timestampOrNil(_ value: Any?) -> Date? {
        if let value = value as? Timestamp { return value.dateValue() }
        return value as? Date
    }

    /// Imported/released-client timestamps come from the device clock rather
    /// than Firestore's commit clock. They are useful ordering hints only while
    /// they remain plausible. If either side of a conflicting source decision
    /// is implausibly far ahead, picking a winner could overwrite the only good
    /// copy of a user's data.
    nonisolated static func importedTimestampOrderingIsAmbiguous(
        _ lhs: Date,
        _ rhs: Date
    ) -> Bool {
        isImplausiblyFutureTimestamp(lhs) || isImplausiblyFutureTimestamp(rhs)
    }

    nonisolated private static func firestoreTimestamp(_ date: Date) -> Any {
        if date == .distantPast
            || date.timeIntervalSinceNow > maximumImportedTimestampSkew {
            // Legacy/imported timestamps can come from a manually set device
            // clock. Once the payload is canonicalized, replace an implausible
            // future value with server time so it cannot outrank real edits for
            // months or years.
            return FieldValue.serverTimestamp()
        }
        return Timestamp(date: date)
    }

    nonisolated private static func isImplausiblyFutureTimestamp(_ value: Any?) -> Bool {
        guard let date = timestampOrNil(value) else { return false }
        return isImplausiblyFutureTimestamp(date)
    }

    nonisolated private static func isImplausiblyFutureTimestamp(_ date: Date) -> Bool {
        date.timeIntervalSinceNow > maximumImportedTimestampSkew
    }

    nonisolated private static func legacyEventTimestamp(in data: [String: Any]) -> Date {
        if let encrypted = data["encrypted"] as? [String: Any],
           encrypted["events"] != nil {
            return timestamp(encrypted["eventsUpdatedAt"] ?? encrypted["updatedAt"])
        }
        let domainTimestamp = max(
            timestamp(data["eventsLastUpdated"]),
            timestamp(data["eventsUpdatedAt"])
        )
        return domainTimestamp == .distantPast
            ? timestamp(data["lastUpdated"] ?? data["updatedAt"])
            : domainTimestamp
    }

    nonisolated private static func legacyScheduleTimestamp(in data: [String: Any]) -> Date {
        if let encrypted = data["encrypted"] as? [String: Any],
           encrypted["schedule"] != nil {
            return timestamp(encrypted["scheduleUpdatedAt"] ?? encrypted["updatedAt"])
        }
        return timestamp(data["lastUpdated"] ?? data["updatedAt"])
    }

    nonisolated private static func scheduleValuesEqual(
        _ lhs: ([ClassItem], ThemeColors, [Bool]),
        _ rhs: ([ClassItem], ThemeColors, [Bool])
    ) -> Bool {
        lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    }

    nonisolated private static func cloudScheduleFingerprint(_ cloud: [String: Any]) -> String {
        [
            "schedule", "theme", "isSecondLunch",
            "scheduleUpdatedAt", "scheduleInitialized", "classTombstones",
            "classTombstoneBases"
        ].map {
            cloud[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
    }

    nonisolated private static func cloudEventsFingerprint(_ cloud: [String: Any]) -> String {
        [
            "events", "eventsUpdatedAt", "eventsInitialized", "eventTombstones",
            "eventTombstoneBases"
        ].map {
            cloud[$0].map(stableValue) ?? "missing"
        }
            .joined(separator: "|")
    }

    nonisolated private static func transitionalCloudFingerprint(
        _ root: [String: Any]
    ) -> String {
        root[transitionalCloudField].map(stableValue) ?? "missing"
    }

    nonisolated private static func releasedScheduleFingerprint(
        _ root: [String: Any]
    ) -> String {
        ["encrypted", "classes", "theme", "isSecondLunch", "lastUpdated"].map {
            root[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
    }

    nonisolated private static func releasedEventsFingerprint(
        _ root: [String: Any]
    ) -> String {
        ["eventsEncrypted", "customEvents", "eventsLastUpdated", "eventsUpdatedAt"].map {
            root[$0].map(stableValue) ?? "missing"
        }.joined(separator: "|")
    }
}
