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
    @Published private(set) var cloudSyncPhase: CloudSyncPhase = .disconnected
    @Published private(set) var lastCloudSyncDate: Date?

    private let userDefaults: UserDefaults
    private let cloudSync: any EventsCloudSyncing
    private let cloudLoadRetryDelays: [Duration]
    private let cloudSaveDebounce: Duration
    private let cloudSaveRetryDelay: Duration
    private let connectivity: any CloudConnectivityChecking
    private let eventsKey    = "CustomEvents"
    private let pendingCloudEventsKeyPrefix = "PendingCloudEvents"
    private let lastSyncedCloudEventsKeyPrefix = "LastSyncedCloudEvents"
    private let establishedCloudBaselineKeyPrefix = "EstablishedCloudEventsBaseline"
    private let localEventsSnapshotKeyPrefix = "LocalCustomEvents"
    private let localEventsOwnerKey = "LocalCustomEventsOwner"
    private let corruptLocalEventsMessage =
        "This account's saved events could not be read. Cloud sync was stopped before any cloud data was changed."
    private var authManager: AuthenticationManager?
    private var isPurgingExpiredReminders = false
    private var cloudSaveTask: Task<Void, Never>?
    private var cloudSaveRetryTask: Task<Void, Never>?
    private var cloudLoadTask: Task<Void, Never>?
    private var cloudLoadRetryTask: Task<Void, Never>?
    private var cloudObservation: CloudSyncObservation?
    private var cloudLoadedUserID: String?
    private var cloudLoadAttempt = 0
    private var cloudLoadGeneration = 0
    private var pendingCloudUserID: String?
    private var hasPendingCloudEvents = false
    private var lastSyncedCloudEvents: [CustomEvent] = []
    private var hasEstablishedCloudBaseline = false
    private var blockedLocalEventsScope: String?

    init(
        userDefaults: UserDefaults = .standard,
        cloudSync: (any EventsCloudSyncing)? = nil,
        cloudLoadRetryDelays: [Duration] = [
            .seconds(2),
            .seconds(5),
            .seconds(10)
        ],
        cloudSaveDebounce: Duration = .milliseconds(750),
        cloudSaveRetryDelay: Duration = .seconds(5),
        connectivity: any CloudConnectivityChecking = NetworkCloudConnectivity.shared
    ) {
        self.userDefaults = userDefaults
        self.cloudSync = cloudSync ?? CloudEventsDataManager.shared
        self.cloudLoadRetryDelays = cloudLoadRetryDelays
        self.cloudSaveDebounce = cloudSaveDebounce
        self.cloudSaveRetryDelay = cloudSaveRetryDelay
        self.connectivity = connectivity
        loadEvents()
    }

    func setAuthManager(_ manager: AuthenticationManager) {
        authManager = manager
    }

    // MARK: - Persistence

    func saveEvents(syncToCloud: Bool = true) {
        do {
            let userID = authManager?.user?.id ?? locallyOwnedEventsUserID()
            guard allowLocalEventsMutation(for: userID) else { return }
            if syncToCloud {
                markPendingCloudEvents(for: userID)
            }

            // Persist the complete UID-scoped payload before the legacy global
            // copies. If a later write is interrupted, relaunch restores this
            // snapshot instead of treating a partial/invalid global value as an
            // authoritative deletion.
            persistLocalEventsSnapshot(for: userID)
            let data = try JSONEncoder().encode(events)
            if userDefaults.data(forKey: eventsKey) != data {
                userDefaults.set(data, forKey: eventsKey)
                SharedGroup.defaults.set(data, forKey: "CustomEvents")
                NotificationManager.shared.scheduleReminderNotifications(for: events)
            }

            if syncToCloud {
                queueCloudSave()
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

    func loadFromCloud(using authManager: AuthenticationManager) {
        persistLocalEventsSnapshot(for: pendingCloudUserID)
        self.authManager = authManager
        loadPendingCloudEvents(for: authManager.user?.id)
        let activatedLocalEvents = activateLocalEvents(for: authManager.user?.id)
        guard activatedLocalEvents else { return }
        cloudSyncPhase = authManager.user == nil
            ? .disconnected
            : (hasPendingCloudEvents ? .pending : .loading)
        syncCloudData()
    }

    func handleUserChange(using authManager: AuthenticationManager) {
        let previousUserID = pendingCloudUserID
        persistLocalEventsSnapshot(for: pendingCloudUserID)
        self.authManager = authManager
        cloudSaveTask?.cancel()
        cloudSaveRetryTask?.cancel()
        cloudLoadGeneration += 1
        cloudLoadTask?.cancel()
        cloudLoadTask = nil
        cloudLoadRetryTask?.cancel()
        cloudObservation?.cancel()
        cloudObservation = nil
        cloudLoadedUserID = nil
        cloudLoadAttempt = 0
        loadPendingCloudEvents(for: authManager.user?.id)
        let activatedLocalEvents = activateLocalEvents(
            for: authManager.user?.id,
            switchToGuest: authManager.user == nil && previousUserID != nil
        )
        guard activatedLocalEvents else { return }
        cloudSyncPhase = authManager.user == nil ? .disconnected : .loading
        syncCloudData()
    }

    func retryCloudSync(force: Bool = false) {
        guard let userID = authManager?.user?.id else { return }
        guard !isLocalEventsBlocked(for: userID) else {
            cloudSyncPhase = .failed(corruptLocalEventsMessage)
            return
        }
        if !force, cloudLoadedUserID == userID {
            queueCloudSave()
            return
        }
        if force {
            cloudLoadGeneration += 1
            cloudLoadTask?.cancel()
            cloudLoadTask = nil
        }
        cloudSyncPhase = .loading
        cloudLoadAttempt = 0
        cloudLoadRetryTask?.cancel()
        syncCloudData(force: force)
    }

    func refreshCloudSync() async {
        retryCloudSync(force: true)
        await cloudLoadTask?.value
    }

    func flushCloudSync() async {
        cloudSaveTask?.cancel()
        cloudSaveRetryTask?.cancel()
        guard hasPendingCloudEvents,
              let userID = authManager?.user?.id,
              cloudLoadedUserID == userID else { return }
        guard !isLocalEventsBlocked(for: userID) else {
            cloudSyncPhase = .failed(corruptLocalEventsMessage)
            return
        }

        let eventsToSave = events
        do {
            guard connectivity.isConnected else { throw CloudConnectivityError.offline }
            try await cloudSync.saveEvents(eventsToSave, for: userID)
            if events == eventsToSave {
                hasPendingCloudEvents = false
                persistPendingCloudEvents()
                lastSyncedCloudEvents = eventsToSave
                persistLastSyncedCloudEvents()
            }
            lastCloudSyncDate = Date()
            cloudSyncPhase = hasPendingCloudEvents ? .pending : .synced
        } catch {
            print("❌ Failed to flush events to cloud: \(error)")
            cloudSyncPhase = .failed(error.localizedDescription)
            scheduleCloudSaveRetry(userID: userID)
        }
    }

    private func syncCloudData(force: Bool = false) {
        guard let userId = authManager?.user?.id else { return }
        guard !isLocalEventsBlocked(for: userId) else {
            cloudSyncPhase = .failed(corruptLocalEventsMessage)
            return
        }
        guard connectivity.isConnected else {
            cloudSyncPhase = .failed(CloudConnectivityError.offline.localizedDescription)
            return
        }
        guard force || cloudLoadedUserID != userId else {
            queueCloudSave()
            return
        }
        guard cloudLoadTask == nil else { return }

        cloudLoadGeneration += 1
        let generation = cloudLoadGeneration
        cloudLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if cloudLoadGeneration == generation {
                    cloudLoadTask = nil
                }
            }

            do {
                guard connectivity.isConnected else { throw CloudConnectivityError.offline }
                let cloudState = try await cloudSync.loadEventState(for: userId)
                guard !Task.isCancelled,
                      cloudLoadGeneration == generation,
                      authManager?.user?.id == userId else { return }

                cloudLoadedUserID = userId
                cloudLoadAttempt = 0
                cloudLoadRetryTask?.cancel()
                lastCloudSyncDate = Date()
                cloudSyncPhase = hasPendingCloudEvents ? .pending : .synced

                if !cloudState.isAuthoritative {
                    // A missing shared user document is not an instruction to
                    // delete every event. Recover the last durable account
                    // snapshot and queue it for reconstruction. An encoded []
                    // remains authoritative and follows the normal path below.
                    if !hasPendingCloudEvents,
                       events.isEmpty,
                       !lastSyncedCloudEvents.isEmpty {
                        events = lastSyncedCloudEvents
                    }
                    if hasPendingCloudEvents || !events.isEmpty {
                        markPendingCloudEvents(for: userId)
                        saveEvents(syncToCloud: false)
                    }
                    startCloudObservation(for: userId)
                    queueCloudSave()
                    return
                }

                let cloudEvents = cloudState.events

                let shouldPreserveLocalEvents = shouldPreserveLocalEvents(
                    against: cloudEvents
                )
                if shouldPreserveLocalEvents {
                    // Persist pending before the baseline bit. If the process is
                    // interrupted between these writes, the next launch still
                    // merges and uploads the durable local payload.
                    markPendingCloudEvents(for: userId)
                }
                establishCloudBaseline()

                if hasPendingCloudEvents {
                    events = Self.mergeEvents(
                        base: lastSyncedCloudEvents,
                        local: events,
                        remote: cloudEvents
                    )
                    saveEvents(syncToCloud: false)
                } else {
                    events = cloudEvents
                    purgeExpiredReminders()
                    // Loading cloud state is not itself a user change, so only
                    // persist it locally. A purge still queues its real change.
                    saveEvents(syncToCloud: false)
                }
                lastSyncedCloudEvents = cloudEvents
                persistLastSyncedCloudEvents()
                startCloudObservation(for: userId)
                queueCloudSave()
            } catch is CancellationError {
                return
            } catch {
                print("❌ Failed to load events from cloud: \(error)")
                cloudSyncPhase = .failed(error.localizedDescription)
                guard cloudLoadGeneration == generation,
                      authManager?.user?.id == userId else { return }
                scheduleCloudLoadRetry(userID: userId)
            }
        }
    }

    private func startCloudObservation(for userID: String) {
        cloudObservation?.cancel()
        cloudObservation = cloudSync.observeEvents(for: userID) { [weak self] result in
            guard let self,
                  authManager?.user?.id == userID,
                  cloudLoadedUserID == userID else { return }

            switch result {
            case .success(let remoteEvents):
                let shouldPreserveLocalEvents = shouldPreserveLocalEvents(
                    against: remoteEvents
                )
                if shouldPreserveLocalEvents {
                    markPendingCloudEvents(for: userID)
                }
                establishCloudBaseline()

                if hasPendingCloudEvents {
                    let merged = Self.mergeEvents(
                        base: lastSyncedCloudEvents,
                        local: events,
                        remote: remoteEvents
                    )
                    lastSyncedCloudEvents = remoteEvents
                    persistLastSyncedCloudEvents()
                    if events != merged {
                        events = merged
                        saveEvents(syncToCloud: false)
                    }
                    queueCloudSave()
                } else {
                    lastSyncedCloudEvents = remoteEvents
                    persistLastSyncedCloudEvents()
                    guard events != remoteEvents else { return }
                    // An empty array is meaningful: another device may have
                    // deleted the final event.
                    events = remoteEvents
                    purgeExpiredReminders()
                    saveEvents(syncToCloud: false)
                }
                lastCloudSyncDate = Date()
                cloudSyncPhase = hasPendingCloudEvents ? .pending : .synced
            case .failure(let error):
                print("❌ Events live sync listener failed: \(error)")
                cloudSyncPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func queueCloudSave() {
        cloudSaveTask?.cancel()
        cloudSaveRetryTask?.cancel()
        guard hasPendingCloudEvents else { return }
        guard let userId = authManager?.user?.id else { return }
        guard !isLocalEventsBlocked(for: userId) else {
            cloudSyncPhase = .failed(corruptLocalEventsMessage)
            return
        }
        guard cloudLoadedUserID == userId else {
            syncCloudData()
            return
        }
        let eventsToSave = events

        cloudSaveTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: cloudSaveDebounce)
                guard !Task.isCancelled,
                      hasPendingCloudEvents,
                      authManager?.user?.id == userId else { return }
                guard connectivity.isConnected else { throw CloudConnectivityError.offline }
                try await cloudSync.saveEvents(eventsToSave, for: userId)
                if events == eventsToSave {
                    hasPendingCloudEvents = false
                    persistPendingCloudEvents()
                    lastSyncedCloudEvents = eventsToSave
                    persistLastSyncedCloudEvents()
                }
                lastCloudSyncDate = Date()
                cloudSyncPhase = hasPendingCloudEvents ? .pending : .synced
            } catch is CancellationError {
                // A newer event change replaced this pending save.
            } catch {
                print("❌ Failed to auto-save events to cloud: \(error)")
                self?.cloudSyncPhase = .failed(error.localizedDescription)
                self?.scheduleCloudSaveRetry(userID: userId)
            }
        }
    }

    private func scheduleCloudLoadRetry(userID: String) {
        cloudLoadAttempt += 1
        guard cloudLoadAttempt <= cloudLoadRetryDelays.count else { return }

        cloudLoadRetryTask?.cancel()
        let delay = cloudLoadRetryDelays[cloudLoadAttempt - 1]
        cloudLoadRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self,
                      authManager?.user?.id == userID else { return }
                cloudLoadRetryTask = nil
                syncCloudData()
            } catch {
                return
            }
        }
    }

    private func scheduleCloudSaveRetry(userID: String) {
        cloudSaveRetryTask?.cancel()
        cloudSaveRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.cloudSaveRetryDelay ?? .seconds(5))
                guard let self,
                      authManager?.user?.id == userID else { return }
                cloudSaveRetryTask = nil
                queueCloudSave()
            } catch {
                return
            }
        }
    }

    private func markPendingCloudEvents(for userID: String?) {
        guard let userID else { return }
        if pendingCloudUserID != userID {
            loadPendingCloudEvents(for: userID)
        }
        hasPendingCloudEvents = true
        cloudSyncPhase = .pending
        persistPendingCloudEvents()
    }

    private func loadPendingCloudEvents(for userID: String?) {
        pendingCloudUserID = userID
        hasPendingCloudEvents = userDefaults.bool(
            forKey: pendingCloudEventsKey(for: userID)
        )
        lastSyncedCloudEvents = loadLastSyncedCloudEvents(for: userID)

        guard userID != nil else {
            hasEstablishedCloudBaseline = false
            return
        }

        let baselineKey = establishedCloudBaselineKey(for: userID)
        if userDefaults.object(forKey: baselineKey) != nil {
            hasEstablishedCloudBaseline = userDefaults.bool(forKey: baselineKey)
        } else {
            // Existing installs already persisted last-synced data after a
            // successful cloud read. Its key presence, including encoded [],
            // is therefore a trustworthy baseline seed during this rollout.
            hasEstablishedCloudBaseline = userDefaults.object(
                forKey: lastSyncedCloudEventsKey(for: userID)
            ) != nil
            if hasEstablishedCloudBaseline {
                persistEstablishedCloudBaseline()
            }
        }
    }

    private func persistPendingCloudEvents() {
        userDefaults.set(
            hasPendingCloudEvents,
            forKey: pendingCloudEventsKey(for: pendingCloudUserID)
        )
    }

    private func pendingCloudEventsKey(for userID: String?) -> String {
        "\(pendingCloudEventsKeyPrefix).\(userID ?? "guest")"
    }

    private func lastSyncedCloudEventsKey(for userID: String?) -> String {
        "\(lastSyncedCloudEventsKeyPrefix).\(userID ?? "guest")"
    }

    private func establishedCloudBaselineKey(for userID: String?) -> String {
        "\(establishedCloudBaselineKeyPrefix).\(userID ?? "guest")"
    }

    private func localEventsSnapshotKey(for userID: String?) -> String {
        "\(localEventsSnapshotKeyPrefix).\(userID ?? "guest")"
    }

    private func localEventsScope(for userID: String?) -> String {
        userID.map { "user:\($0)" } ?? "guest"
    }

    private func isLocalEventsBlocked(for userID: String?) -> Bool {
        let targetScope = localEventsScope(for: userID)
        if blockedLocalEventsScope == targetScope { return true }

        let snapshotKey = localEventsSnapshotKey(for: userID)
        guard let snapshotData = userDefaults.data(forKey: snapshotKey) else {
            return false
        }
        guard (try? JSONDecoder().decode(
            [CustomEvent].self,
            from: snapshotData
        )) == nil else {
            return false
        }

        blockedLocalEventsScope = targetScope
        return true
    }

    private func allowLocalEventsMutation(for userID: String?) -> Bool {
        guard !isLocalEventsBlocked(for: userID) else {
            cloudSyncPhase = .failed(corruptLocalEventsMessage)
            return false
        }
        return true
    }

    private func locallyOwnedEventsUserID() -> String? {
        guard let owner = userDefaults.string(forKey: localEventsOwnerKey),
              owner.hasPrefix("user:") else { return nil }
        return String(owner.dropFirst("user:".count))
    }

    private func persistLocalEventsSnapshot(for userID: String?) {
        let owner = userDefaults.string(forKey: localEventsOwnerKey)
        let targetScope = localEventsScope(for: userID)
        guard !isLocalEventsBlocked(for: userID) else { return }
        // Before the first authenticated account claims the legacy global
        // payload it is intentionally unowned. Likewise, never copy an active
        // account's global payload into a different account/guest snapshot.
        guard owner == targetScope || (owner == nil && userID != nil) else { return }
        guard let data = try? JSONEncoder().encode(events) else { return }
        userDefaults.set(data, forKey: localEventsSnapshotKey(for: userID))
    }

    /// The legacy events array was global while its pending marker was scoped
    /// by UID. Restore a UID-scoped payload before any cloud merge so an
    /// offline edit from one account can never be replaced by, or uploaded
    /// into, another account.
    private func activateLocalEvents(
        for userID: String?,
        switchToGuest: Bool = false
    ) -> Bool {
        let targetScope = localEventsScope(for: userID)
        let currentOwner = userDefaults.string(forKey: localEventsOwnerKey)
        if userID == nil,
           currentOwner?.hasPrefix("user:") == true,
           !switchToGuest {
            // Firebase Auth may briefly publish nil while restoring a session.
            // Do not reinterpret that startup state as an explicit sign-out.
            return true
        }
        blockedLocalEventsScope = nil
        let snapshotData = userDefaults.data(forKey: localEventsSnapshotKey(for: userID))
        let snapshot = snapshotData.flatMap {
            try? JSONDecoder().decode([CustomEvent].self, from: $0)
        }

        if snapshotData != nil, snapshot == nil {
            blockedLocalEventsScope = targetScope
            // A corrupt selected-account snapshot must never leave the prior
            // account visible or eligible for a later foreground retry/upload.
            // For the same account, retain the legacy global copy in memory as
            // a recovery aid while all persistence and cloud writes stay fenced.
            if currentOwner != targetScope {
                // Preserve a pre-scoped-snapshot owner's only unsynced legacy
                // copy before privacy-blanking this selected account. Without
                // this, a later guest transition could erase the prior owner.
                persistLocalEventsSnapshot(for: locallyOwnedEventsUserID())
                blockedLocalEventsScope = targetScope
                events = []
            }
            cloudSyncPhase = .failed(corruptLocalEventsMessage)
            return false
        }

        if let snapshot {
            // The scoped snapshot is updated before the legacy global value on
            // every edit. Prefer it even when the owner matches so a corrupt or
            // partially written global payload cannot erase account data.
            events = snapshot
        } else if currentOwner == targetScope {
            // Backward compatibility for an account whose global events value
            // predates scoped snapshots. The final write below seeds one.
        } else if currentOwner != nil && currentOwner != targetScope {
            // Do not expose the previous account while this account's cloud
            // snapshot is loading. A real authoritative empty cloud result is
            // still handled by the normal baseline logic.
            events = []
        }

        if let userID {
            if currentOwner == nil {
                userDefaults.removeObject(forKey: localEventsSnapshotKey(for: nil))
            }
            userDefaults.set(localEventsScope(for: userID), forKey: localEventsOwnerKey)
        } else if currentOwner != nil {
            userDefaults.set(targetScope, forKey: localEventsOwnerKey)
        }

        if let data = try? JSONEncoder().encode(events) {
            userDefaults.set(data, forKey: eventsKey)
            SharedGroup.defaults.set(data, forKey: "CustomEvents")
        }
        NotificationManager.shared.scheduleReminderNotifications(for: events)
        persistLocalEventsSnapshot(for: userID)
        return true
    }

    private func shouldPreserveLocalEvents(against remoteEvents: [CustomEvent]) -> Bool {
        !hasEstablishedCloudBaseline
            && !hasPendingCloudEvents
            && !events.isEmpty
            && remoteEvents.isEmpty
    }

    private func establishCloudBaseline() {
        guard !hasEstablishedCloudBaseline, pendingCloudUserID != nil else { return }
        hasEstablishedCloudBaseline = true
        persistEstablishedCloudBaseline()
    }

    private func persistEstablishedCloudBaseline() {
        guard pendingCloudUserID != nil else { return }
        userDefaults.set(
            hasEstablishedCloudBaseline,
            forKey: establishedCloudBaselineKey(for: pendingCloudUserID)
        )
    }

    private func loadLastSyncedCloudEvents(for userID: String?) -> [CustomEvent] {
        guard let data = userDefaults.data(
            forKey: lastSyncedCloudEventsKey(for: userID)
        ) else { return [] }
        return (try? JSONDecoder().decode([CustomEvent].self, from: data)) ?? []
    }

    private func persistLastSyncedCloudEvents() {
        guard let data = try? JSONEncoder().encode(lastSyncedCloudEvents) else { return }
        userDefaults.set(
            data,
            forKey: lastSyncedCloudEventsKey(for: pendingCloudUserID)
        )
    }

    /// Three-way merge for multi-device edits. An unchanged side accepts the
    /// other side's add/edit/delete. If both sides changed the same event,
    /// edits are preserved over deletion and the local edit wins only when
    /// both sides contain conflicting edited values.
    nonisolated static func mergeEvents(
        base: [CustomEvent],
        local: [CustomEvent],
        remote: [CustomEvent]
    ) -> [CustomEvent] {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(baseByID.keys).union(localByID.keys).union(remoteByID.keys)

        return ids.compactMap { id -> CustomEvent? in
            let baseValue = baseByID[id]
            let localValue = localByID[id]
            let remoteValue = remoteByID[id]

            if localValue == baseValue { return remoteValue }
            if remoteValue == baseValue { return localValue }
            if localValue == remoteValue { return localValue }

            // A delete racing an edit should never destroy the edited value.
            if localValue == nil { return remoteValue }
            if remoteValue == nil { return localValue }
            return localValue
        }
        .sorted { lhs, rhs in
            if lhs.startTime.seconds != rhs.startTime.seconds {
                return lhs.startTime.seconds < rhs.startTime.seconds
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Event Management (all on MainActor — no queue needed)

    /// Adds a new event. Identical to addEventSync; kept for call-site compat.
    func addEvent(_ event: CustomEvent) {
        let userID = authManager?.user?.id ?? locallyOwnedEventsUserID()
        guard allowLocalEventsMutation(for: userID) else { return }
        events.append(event)
        saveEvents()
        UsageStatsStore.shared.recordItemAction(.create, for: usageItemKind(for: event))
    }

    /// Updates an existing event in-place.
    func updateEvent(_ event: CustomEvent) {
        let userID = authManager?.user?.id ?? locallyOwnedEventsUserID()
        guard allowLocalEventsMutation(for: userID) else { return }
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        guard events[index] != event else { return }
        events[index] = event
        saveEvents()
        UsageStatsStore.shared.recordItemAction(.edit, for: usageItemKind(for: event))
    }

    /// Removes an event. Fix 4: now atomic — no barrier/main-thread split.
    func deleteEvent(_ event: CustomEvent) {
        let userID = authManager?.user?.id ?? locallyOwnedEventsUserID()
        guard allowLocalEventsMutation(for: userID) else { return }
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        let removedEvent = events.remove(at: index)
        saveEvents()
        UsageStatsStore.shared.recordItemAction(.delete, for: usageItemKind(for: removedEvent))
    }

    // These remain for call sites that use the "Sync" suffix
    func addEventSync(_ event: CustomEvent)    { addEvent(event) }
    func updateEventSync(_ event: CustomEvent) { updateEvent(event) }

    private func usageItemKind(for event: CustomEvent) -> UsageItemKind {
        event.isReminder ? .reminder : .event
    }

    // MARK: - Event Filtering

    func eventsFor(dayCode: String, date: Date) -> [CustomEvent] {
        purgeExpiredReminders()
        return events.filter { $0.appliesTo(dayCode: dayCode, date: date) }
    }

    func purgeExpiredReminders(referenceDate: Date = Date()) {
        guard !isPurgingExpiredReminders else { return }
        let userID = authManager?.user?.id ?? locallyOwnedEventsUserID()
        guard allowLocalEventsMutation(for: userID) else { return }

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
