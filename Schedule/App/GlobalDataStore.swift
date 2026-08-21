//
//  GlobalDataStore.swift
//  Schedule
//

import Foundation
import SwiftUI

@MainActor
final class GlobalDataStore: ObservableObject {
    private struct LocalScheduleSnapshot: Codable {
        let classes: [ClassItem]
        let isSecondLunch: [Bool]
        let theme: ThemeColors
    }

    private enum PendingCloudField: String, CaseIterable {
        case classes
        case theme
        case isSecondLunch
    }

    @Published var output = "Loading…"
    @Published var dayCode = ""
    @Published var note = ""
    @Published var scheduleDict: [String: [String]]? = nil
    @Published var scheduleLines: [ScheduleLine] = []
    @Published var data: ScheduleData? = nil
    @Published var selectedDate = Date()
    @Published var scheduleLoadError: String? = nil
    @Published var scheduleRetryAttempt: Int = 0
    @Published private(set) var cloudSyncPhase: CloudSyncPhase = .disconnected
    @Published private(set) var lastCloudSyncDate: Date?

    @Published var primaryColor: Color = .blue
    @Published var secondaryColor: Color = .blue.opacity(0.1)
    @Published var tertiaryColor: Color = .primary
    @Published var primaryFontChoice: AppFontChoice = .rounded
    @Published var secondaryFontChoice: AppFontChoice = .rounded

    private let persistence: CloudService
    private let cloudSync: any ScheduleCloudSyncing
    private let userDefaults: UserDefaults
    private let cloudLoadRetryDelays: [Duration]
    private let cloudSaveDebounce: Duration
    private let cloudSaveRetryDelay: Duration
    private let connectivity: any CloudConnectivityChecking

    private var cloudSaveTask: Task<Void, Never>?
    private var cloudSaveRetryTask: Task<Void, Never>?
    private var cloudLoadTask: Task<Void, Never>?
    private var cloudRetryTask: Task<Void, Never>?
    private var cloudObservation: CloudSyncObservation?
    private var cloudLoadedUserID: String?
    private var cloudLoadAttempt = 0
    private var cloudLoadGeneration = 0
    private var pendingCloudFields: Set<PendingCloudField> = []
    private var pendingCloudUserID: String?
    private var lastSyncedCloudClasses: [ClassItem] = []
    private var requiresCloudRewrite = false
    private let pendingCloudFieldsKeyPrefix = "PendingCloudScheduleFields"
    private let lastSyncedCloudClassesKeyPrefix = "LastSyncedCloudClasses"
    private let localScheduleSnapshotKeyPrefix = "LocalScheduleSnapshot"
    private let localScheduleOwnerKey = "LocalScheduleOwner"
    private let corruptLocalScheduleMessage =
        "This account's saved schedule could not be read. Cloud sync was stopped before any cloud data was changed."
    private var blockedLocalScheduleScope: String?
    private var hasTriedFetchingSchedule = false
    private var scheduleFetchTask: Task<Void, Never>?
    private var specialCodeFetchTask: Task<Void, Never>?
    private var specialCodeFetchKey: String?

    init() {
        let persistence = CloudService()
        self.persistence = persistence
        self.cloudSync = persistence
        self.userDefaults = .standard
        self.cloudLoadRetryDelays = [
            .seconds(2),
            .seconds(5),
            .seconds(10)
        ]
        self.cloudSaveDebounce = .seconds(1)
        self.cloudSaveRetryDelay = .seconds(5)
        self.connectivity = NetworkCloudConnectivity.shared
    }

    init(
        persistence: CloudService,
        cloudSync: (any ScheduleCloudSyncing)? = nil,
        userDefaults: UserDefaults = .standard,
        cloudLoadRetryDelays: [Duration] = [
            .seconds(2),
            .seconds(5),
            .seconds(10)
        ],
        cloudSaveDebounce: Duration = .seconds(1),
        cloudSaveRetryDelay: Duration = .seconds(5),
        connectivity: any CloudConnectivityChecking = NetworkCloudConnectivity.shared
    ) {
        self.persistence = persistence
        self.cloudSync = cloudSync ?? persistence
        self.userDefaults = userDefaults
        self.cloudLoadRetryDelays = cloudLoadRetryDelays
        self.cloudSaveDebounce = cloudSaveDebounce
        self.cloudSaveRetryDelay = cloudSaveRetryDelay
        self.connectivity = connectivity
    }

    var currentTheme: ThemeColors {
        ThemeColors(
            primary: primaryColor.toHex() ?? "#00A5FFFF",
            secondary: secondaryColor.toHex() ?? "#00A5FF19",
            tertiary: tertiaryColor.toHex() ?? "#FFFFFFFF",
            primaryFont: primaryFontChoice,
            secondaryFont: secondaryFontChoice
        )
    }

    var pendingCloudChangeCount: Int {
        pendingCloudFields.count + (requiresCloudRewrite ? 1 : 0)
    }

    func loadData(
        authManager: AuthenticationManager,
        eventsManager: CustomEventsManager,
        onboardingClasses: [ClassItem]
    ) {
        guard data == nil else { return }

        loadPendingCloudFields(for: authManager.user?.id)
        applyLocalData(
            onboardingClasses: onboardingClasses,
            events: eventsManager.events
        )
        let activatedLocalSchedule = activateLocalSchedule(for: authManager.user?.id)
        if AppRuntime.isUITesting,
           !AppRuntime.simulatesUncachedScheduleRetry,
           scheduleDict == nil {
            scheduleDict = [:]
        }
        if AppRuntime.simulatesActiveScheduleRetry || AppRuntime.simulatesUncachedScheduleRetry {
            scheduleRetryAttempt = 1
        } else if AppRuntime.simulatesScheduleRefreshFailure {
            scheduleLoadError = "Couldn’t refresh. Showing the last saved schedule."
        }
        if activatedLocalSchedule {
            syncCloudData(authManager: authManager)
        }
        eventsManager.setAuthManager(authManager)
        eventsManager.loadFromCloud(using: authManager)

        if !hasTriedFetchingSchedule {
            hasTriedFetchingSchedule = true
            if !AppRuntime.isUITesting {
                fetchScheduleFromGoogleSheets(events: eventsManager.events)
            }
        }
    }

    func saveTheme(authManager: AuthenticationManager) {
        guard !AppRuntime.isUITesting else { return }
        let userID = authManager.user?.id ?? locallyOwnedScheduleUserID()
        guard allowLocalScheduleMutation(for: userID) else { return }
        markPending(.theme, userID: userID)
        // The UID-scoped snapshot is the durable source of truth. Update it
        // before the legacy global copies so an interrupted write cannot make a
        // partial global payload outrank the complete account snapshot.
        persistLocalScheduleSnapshot(for: userID)
        saveThemeLocally(currentTheme)
        queueCloudSave(authManager: authManager)
    }

    func saveSchedule(authManager: AuthenticationManager) {
        guard let data else { return }
        let userID = authManager.user?.id ?? locallyOwnedScheduleUserID()
        guard allowLocalScheduleMutation(for: userID) else { return }
        persistLocalScheduleSnapshot(for: userID)
        overwriteClassesFile(with: data.classes)
        persistence.saveLunchPreferenceLocally(data.isSecondLunch)
        guard !AppRuntime.isUITesting else { return }
        markPending(.classes, userID: userID)
        queueCloudSave(authManager: authManager)
    }

    func updateSchedule(_ newValue: ScheduleData, authManager: AuthenticationManager) {
        let userID = authManager.user?.id ?? locallyOwnedScheduleUserID()
        guard allowLocalScheduleMutation(for: userID) else { return }
        let normalized = newValue.normalized()
        let previous = data
        data = normalized
        let classesChanged = previous?.classes != normalized.classes
        let lunchChanged = previous?.isSecondLunch != normalized.isSecondLunch

        if classesChanged {
            if !AppRuntime.isUITesting {
                markPending(.classes, userID: userID)
            }
        }
        if lunchChanged {
            if !AppRuntime.isUITesting {
                markPending(.isSecondLunch, userID: userID)
            }
        }

        // Commit the complete scoped payload before updating either legacy
        // global field. This makes relaunch recovery safe after a partial write.
        persistLocalScheduleSnapshot(for: userID)
        if classesChanged {
            overwriteClassesFile(with: normalized.classes)
        }
        if lunchChanged {
            persistence.saveLunchPreferenceLocally(normalized.isSecondLunch)
        }

        if !pendingCloudFields.isEmpty {
            queueCloudSave(authManager: authManager)
        }
    }

    func getDayInfo(for currentDay: String) -> Day? {
        let dayIndex = getDayNumber(for: currentDay) ?? 0
        return data?.days[dayIndex]
    }

    func applySelectedDate(_ date: Date, events: [CustomEvent]) {
        selectedDate = date
        let resolved = ScheduleSelectionResolver.resolve(
            selectedDate: date,
            scheduleDict: scheduleDict,
            data: data,
            events: events
        )

        dayCode = resolved.dayCode
        note = resolved.note
        output = resolved.output
        scheduleLines = resolved.scheduleLines
        SharedGroup.defaults.set(dayCode == "None" ? "" : dayCode, forKey: "CurrentDayCode")

        if dayCode.caseInsensitiveCompare("s1") == .orderedSame,
           (scheduleDict?[ScheduleSelectionResolver.scheduleKey(for: date)]?.count ?? 0) < 3 {
            fetchSpecialCode(for: date, events: events)
        }
    }

    func syncDerivedOutputs(events: [CustomEvent]) {
        refreshRenderedSchedule(events: events)
        guard !AppRuntime.isUITesting else { return }
        saveDataForWidget(reloadTimeline: false)
        saveScheduleLinesWithEvents(events: events, reloadTimeline: true)
        updateLiveActivity()
    }

    func updateCurrentScheduleProgress() {
        scheduleLines = ScheduleRenderer.shared.refreshingProgress(
            in: scheduleLines,
            selectedDate: selectedDate
        )
    }

    func refreshAllData(
        authManager: AuthenticationManager,
        events: [CustomEvent]
    ) async {
        await fetchScheduleFromGoogleSheetsAsync(events: events)
        retryCloudSync(authManager: authManager, force: true)
    }

    func updateNightlyNotification() {
        let context = NightlyNotificationBuilder.makeContext(
            scheduleDict: scheduleDict,
            data: data
        )

        NotificationManager.shared.scheduleNightly(
            dayCode: context.dayCode,
            firstClassName: context.firstClassName,
            firstClassTime: context.firstClassTime,
            firstClassRoom: context.firstClassRoom
        )
    }

    func applyOnboardingClassesIfNeeded(_ onboardingClasses: [ClassItem]) {
        guard !onboardingClasses.isEmpty else { return }
        guard allowLocalScheduleMutation(for: pendingCloudUserID) else { return }
        guard var currentData = data else { return }

        for (index, item) in onboardingClasses.enumerated() {
            guard index < currentData.classes.count else { break }
            let name = item.name.trimmingCharacters(in: .whitespaces)
            let teacher = item.teacher.trimmingCharacters(in: .whitespaces)
            let room = item.room.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { currentData.classes[index].name = name }
            if !teacher.isEmpty { currentData.classes[index].teacher = teacher }
            if !room.isEmpty { currentData.classes[index].room = room }
        }

        data = currentData
        persistLocalScheduleSnapshot(for: pendingCloudUserID)
        overwriteClassesFile(with: currentData.classes)
        saveDataForWidget()
    }

    func resetHomeDateToToday(events: [CustomEvent]) {
        let today = Date()
        selectedDate = today

        if scheduleDict != nil {
            applySelectedDate(today, events: events)
        }
    }

    func handleUserChange(_ userId: String?, authManager: AuthenticationManager) {
        let previousUserID = pendingCloudUserID
        cloudSaveTask?.cancel()
        cloudSaveRetryTask?.cancel()
        cloudLoadGeneration += 1
        cloudLoadTask?.cancel()
        cloudLoadTask = nil
        cloudRetryTask?.cancel()
        cloudObservation?.cancel()
        cloudObservation = nil
        cloudLoadedUserID = nil
        cloudLoadAttempt = 0
        persistLocalScheduleSnapshot(for: pendingCloudUserID)
        loadPendingCloudFields(for: userId)
        let activatedLocalSchedule = activateLocalSchedule(
            for: userId,
            switchToGuest: userId == nil && previousUserID != nil
        )
        if userId != nil {
            guard activatedLocalSchedule else { return }
            cloudSyncPhase = .loading
            syncCloudData(authManager: authManager)
        } else {
            cloudSyncPhase = .disconnected
        }
    }

    func retryCloudSync(authManager: AuthenticationManager, force: Bool = false) {
        guard let userID = authManager.user?.id else { return }
        guard !isLocalScheduleBlocked(for: userID) else {
            cloudSyncPhase = .failed(corruptLocalScheduleMessage)
            return
        }
        if !force, cloudLoadedUserID == userID {
            queueCloudSave(authManager: authManager)
            return
        }
        if force {
            cloudLoadGeneration += 1
            cloudLoadTask?.cancel()
            cloudLoadTask = nil
        }
        cloudSyncPhase = .loading
        cloudLoadAttempt = 0
        cloudRetryTask?.cancel()
        syncCloudData(authManager: authManager, force: force)
    }

    func refreshCloudSync(authManager: AuthenticationManager) async {
        retryCloudSync(authManager: authManager, force: true)
        await cloudLoadTask?.value
    }

    func refreshSchedule(events: [CustomEvent]) async {
        scheduleFetchTask?.cancel()
        await fetchWithRetry(events: events)
    }

    /// Bypasses debounce when iOS is about to suspend the process. Local data
    /// is already durable; this gives pending cloud changes their best chance
    /// to reach Firestore before the background execution window closes.
    func flushCloudSync(authManager: AuthenticationManager) async {
        cloudSaveTask?.cancel()
        cloudSaveRetryTask?.cancel()
        guard !pendingCloudFields.isEmpty || requiresCloudRewrite,
              let data,
              let userID = authManager.user?.id,
              cloudLoadedUserID == userID else { return }
        guard !isLocalScheduleBlocked(for: userID) else {
            cloudSyncPhase = .failed(corruptLocalScheduleMessage)
            return
        }

        let fieldsBeingSaved = pendingCloudFields
        let classes = data.classes
        let theme = currentTheme
        let isSecondLunch = data.isSecondLunch
        do {
            guard connectivity.isConnected else { throw CloudConnectivityError.offline }
            try await cloudSync.saveScheduleToCloud(
                classes: classes,
                theme: theme,
                isSecondLunch: isSecondLunch,
                userId: userID
            )
            clearSavedPendingFields(
                fieldsBeingSaved,
                classes: classes,
                theme: theme,
                isSecondLunch: isSecondLunch
            )
            recordSyncedClassesIfCurrent(fieldsBeingSaved, classes: classes)
            requiresCloudRewrite = false
            lastCloudSyncDate = Date()
            cloudSyncPhase = pendingCloudFields.isEmpty ? .synced : .pending
        } catch {
            print("❌ Failed to flush schedule to cloud: \(error)")
            cloudSyncPhase = .failed(error.localizedDescription)
            scheduleCloudSaveRetry(authManager: authManager, userID: userID)
        }
    }

    func scrollTargetForCurrentSchedule() -> Int {
        ScheduleRenderer.shared.currentClassIndex(in: scheduleLines) ?? 0
    }

    private func applyLocalData(
        onboardingClasses: [ClassItem],
        events: [CustomEvent]
    ) {
        guard let localState = persistence.loadLocalSchedule(
            parseClass: ScheduleParsing.parseClass,
            parseDays: ScheduleParsing.parseDays
        ) else {
            output = "Days.txt not found in bundle."
            return
        }

        applyScheduleState(localState, overwriteClasses: false)
        if AppRuntime.isUITesting {
            applyTheme(
                AppRuntime.usesGraphiteThemeFixture
                    ? ThemeColors(
                        primary: "#D1D1D6FF",
                        secondary: "#D1D1D62E",
                        tertiary: "#FFFFFFFF"
                    )
                    : .defaultTheme
            )
        }
        overwriteClassesFile(with: data?.classes ?? [])
        applyOnboardingClassesIfNeeded(onboardingClasses)
        loadCachedSchedule(events: events)
    }

    private func syncCloudData(
        authManager: AuthenticationManager,
        force: Bool = false
    ) {
        guard let user = authManager.user else { return }
        guard !isLocalScheduleBlocked(for: user.id) else {
            cloudSyncPhase = .failed(corruptLocalScheduleMessage)
            return
        }
        guard connectivity.isConnected else {
            cloudSyncPhase = .failed(CloudConnectivityError.offline.localizedDescription)
            return
        }
        if pendingCloudFields.isEmpty {
            cloudSyncPhase = .loading
        }
        guard force || cloudLoadedUserID != user.id else {
            queueCloudSave(authManager: authManager)
            return
        }
        guard cloudLoadTask == nil else { return }

        cloudLoadGeneration += 1
        let generation = cloudLoadGeneration

        cloudLoadTask = Task { [weak self, weak authManager] in
            guard let self, let authManager else { return }
            defer {
                if cloudLoadGeneration == generation {
                    cloudLoadTask = nil
                }
            }

            do {
                guard connectivity.isConnected else { throw CloudConnectivityError.offline }
                guard let days = data?.days else { return }
                let cloudState = try await cloudSync.loadCloudScheduleState(for: user.id, days: days)
                guard !Task.isCancelled,
                      cloudLoadGeneration == generation,
                      authManager.user?.id == user.id else { return }

                let needsIDMigration = cloudState.classes.contains { $0.needsIDMigration }
                mergeCloudState(cloudState)
                cloudLoadedUserID = user.id
                cloudLoadAttempt = 0
                cloudRetryTask?.cancel()
                requiresCloudRewrite = requiresCloudRewrite || needsIDMigration
                SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
                lastCloudSyncDate = Date()
                cloudSyncPhase = pendingCloudFields.isEmpty ? .synced : .pending
                saveDataForWidget()
                startCloudObservation(for: user.id, days: days, authManager: authManager)
                queueCloudSave(authManager: authManager)
            } catch is CancellationError {
                return
            } catch {
                print("❌ Failed to load from cloud: \(error)")
                cloudSyncPhase = .failed(error.localizedDescription)
                guard cloudLoadGeneration == generation,
                      authManager.user?.id == user.id else { return }
                scheduleCloudLoadRetry(authManager: authManager, userID: user.id)
            }
        }
    }

    private func startCloudObservation(
        for userID: String,
        days: [Day],
        authManager: AuthenticationManager
    ) {
        cloudObservation?.cancel()
        cloudObservation = cloudSync.observeCloudScheduleState(
            for: userID,
            days: days
        ) { [weak self, weak authManager] result in
            guard let self,
                  let authManager,
                  authManager.user?.id == userID,
                  cloudLoadedUserID == userID else { return }

            switch result {
            case .success(let state):
                let previousData = data
                let previousTheme = currentTheme
                mergeCloudState(state)
                if data?.classes != previousData?.classes
                    || data?.isSecondLunch != previousData?.isSecondLunch
                    || currentTheme != previousTheme {
                    SharedGroup.defaults.set(Date(), forKey: "LastAppDataUpdate")
                    saveDataForWidget()
                }
                lastCloudSyncDate = Date()
                cloudSyncPhase = pendingCloudFields.isEmpty ? .synced : .pending
                queueCloudSave(authManager: authManager)
            case .failure(let error):
                print("❌ Schedule live sync listener failed: \(error)")
                cloudSyncPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func saveThemeLocally(_ theme: ThemeColors) {
        persistence.saveThemeLocally(theme)
    }

    private func queueCloudSave(authManager: AuthenticationManager) {
        cloudSaveTask?.cancel()
        cloudSaveRetryTask?.cancel()
        guard !pendingCloudFields.isEmpty || requiresCloudRewrite,
              let data,
              let userId = authManager.user?.id else { return }
        guard !isLocalScheduleBlocked(for: userId) else {
            cloudSyncPhase = .failed(corruptLocalScheduleMessage)
            return
        }

        // Never write an account until its current cloud snapshot has loaded.
        // Otherwise blank/default local state can replace valid remote data.
        guard cloudLoadedUserID == userId else {
            syncCloudData(authManager: authManager)
            return
        }

        let classes = data.classes
        let theme = currentTheme
        let isSecondLunch = data.isSecondLunch
        let fieldsBeingSaved = pendingCloudFields
        cloudSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.cloudSaveDebounce ?? .seconds(1))
                guard !Task.isCancelled,
                      authManager.user?.id == userId,
                      let self else { return }
                guard self.connectivity.isConnected else { throw CloudConnectivityError.offline }
                try await self.cloudSync.saveScheduleToCloud(
                    classes: classes,
                    theme: theme,
                    isSecondLunch: isSecondLunch,
                    userId: userId
                )
                self.clearSavedPendingFields(
                    fieldsBeingSaved,
                    classes: classes,
                    theme: theme,
                    isSecondLunch: isSecondLunch
                )
                self.recordSyncedClassesIfCurrent(fieldsBeingSaved, classes: classes)
                self.requiresCloudRewrite = false
                self.lastCloudSyncDate = Date()
                self.cloudSyncPhase = self.pendingCloudFields.isEmpty ? .synced : .pending
            } catch is CancellationError {
                // A newer edit replaced this pending save.
            } catch {
                print("❌ Failed to save schedule to cloud: \(error)")
                self?.cloudSyncPhase = .failed(error.localizedDescription)
                self?.scheduleCloudSaveRetry(authManager: authManager, userID: userId)
            }
        }
    }

    private func mergeCloudState(_ cloudState: PersistedScheduleState) {
        guard let localData = data else {
            applyScheduleState(cloudState)
            persistLocalScheduleSnapshot(for: pendingCloudUserID)
            return
        }

        let localTheme = currentTheme
        var merged = cloudState.normalizedData
        let usesLocalFallback = !cloudState.isAuthoritative
        if usesLocalFallback {
            merged.classes = localData.classes
            // The cloud record exists for another domain (or not at all) but
            // has never stored a schedule. Make preservation durable before
            // the immediate listener snapshot can arrive.
            pendingCloudFields.formUnion(PendingCloudField.allCases)
            persistPendingCloudFields()
        } else if pendingCloudFields.contains(.classes) {
            merged.classes = Self.mergeClasses(
                base: lastSyncedCloudClasses,
                local: localData.classes,
                remote: merged.classes
            )
        }
        if usesLocalFallback || pendingCloudFields.contains(.isSecondLunch) {
            merged.isSecondLunch = localData.isSecondLunch
        }

        data = merged.normalized()
        if usesLocalFallback || pendingCloudFields.contains(.theme) {
            applyTheme(localTheme)
        } else {
            applyThemeState(cloudState.theme)
        }

        if cloudState.isAuthoritative {
            lastSyncedCloudClasses = cloudState.normalizedData.classes
            persistLastSyncedCloudClasses()
        }
        persistLocalScheduleSnapshot(for: pendingCloudUserID)
        overwriteClassesFile(with: data?.classes ?? merged.classes)
        persistence.saveLunchPreferenceLocally(data?.isSecondLunch ?? merged.isSecondLunch)
        saveThemeLocally(currentTheme)
    }

    private func scheduleCloudLoadRetry(
        authManager: AuthenticationManager,
        userID: String
    ) {
        cloudLoadAttempt += 1
        guard cloudLoadAttempt <= cloudLoadRetryDelays.count else { return }

        cloudRetryTask?.cancel()
        let delay = cloudLoadRetryDelays[cloudLoadAttempt - 1]
        cloudRetryTask = Task { [weak self, weak authManager] in
            do {
                try await Task.sleep(for: delay)
                guard let self,
                      let authManager,
                      authManager.user?.id == userID else { return }
                cloudRetryTask = nil
                syncCloudData(authManager: authManager)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func scheduleCloudSaveRetry(
        authManager: AuthenticationManager,
        userID: String
    ) {
        cloudSaveRetryTask?.cancel()
        cloudSaveRetryTask = Task { [weak self, weak authManager] in
            do {
                try await Task.sleep(for: self?.cloudSaveRetryDelay ?? .seconds(5))
                guard let self,
                      let authManager,
                      authManager.user?.id == userID else { return }
                cloudSaveRetryTask = nil
                queueCloudSave(authManager: authManager)
            } catch {
                return
            }
        }
    }

    private func markPending(_ field: PendingCloudField, userID: String?) {
        guard let userID else { return }
        if pendingCloudUserID != userID {
            loadPendingCloudFields(for: userID)
        }
        pendingCloudFields.insert(field)
        cloudSyncPhase = .pending
        persistPendingCloudFields()
    }

    private func clearSavedPendingFields(
        _ fields: Set<PendingCloudField>,
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool]
    ) {
        if fields.contains(.classes), data?.classes == classes {
            pendingCloudFields.remove(.classes)
        }
        if fields.contains(.theme), currentTheme == theme {
            pendingCloudFields.remove(.theme)
        }
        if fields.contains(.isSecondLunch), data?.isSecondLunch == isSecondLunch {
            pendingCloudFields.remove(.isSecondLunch)
        }
        persistPendingCloudFields()
    }

    private func loadPendingCloudFields(for userID: String?) {
        pendingCloudUserID = userID
        let values = userDefaults.stringArray(
            forKey: pendingCloudFieldsKey(for: userID)
        ) ?? []
        pendingCloudFields = Set(values.compactMap(PendingCloudField.init(rawValue:)))
        lastSyncedCloudClasses = loadLastSyncedCloudClasses(for: userID)
    }

    private func persistPendingCloudFields() {
        let values = pendingCloudFields.map(\.rawValue).sorted()
        userDefaults.set(
            values,
            forKey: pendingCloudFieldsKey(for: pendingCloudUserID)
        )
    }

    private func pendingCloudFieldsKey(for userID: String?) -> String {
        "\(pendingCloudFieldsKeyPrefix).\(userID ?? "guest")"
    }

    private func lastSyncedCloudClassesKey(for userID: String?) -> String {
        "\(lastSyncedCloudClassesKeyPrefix).\(userID ?? "guest")"
    }

    private func localScheduleSnapshotKey(for userID: String?) -> String {
        "\(localScheduleSnapshotKeyPrefix).\(userID ?? "guest")"
    }

    private func localScheduleScope(for userID: String?) -> String {
        userID.map { "user:\($0)" } ?? "guest"
    }

    private func isLocalScheduleBlocked(for userID: String?) -> Bool {
        let targetScope = localScheduleScope(for: userID)
        if blockedLocalScheduleScope == targetScope { return true }

        let snapshotKey = localScheduleSnapshotKey(for: userID)
        guard let encodedSnapshot = userDefaults.data(forKey: snapshotKey) else {
            return false
        }
        guard (try? JSONDecoder().decode(
            LocalScheduleSnapshot.self,
            from: encodedSnapshot
        )) == nil else {
            return false
        }

        // Detect the corrupt durable value at every write/retry boundary, not
        // only during account activation. This prevents an edit made before or
        // after activation from replacing the evidence and bypassing the fence.
        blockedLocalScheduleScope = targetScope
        return true
    }

    private func allowLocalScheduleMutation(for userID: String?) -> Bool {
        guard !isLocalScheduleBlocked(for: userID) else {
            cloudSyncPhase = .failed(corruptLocalScheduleMessage)
            return false
        }
        return true
    }

    private func locallyOwnedScheduleUserID() -> String? {
        guard let owner = userDefaults.string(forKey: localScheduleOwnerKey),
              owner.hasPrefix("user:") else { return nil }
        return String(owner.dropFirst("user:".count))
    }

    private func persistLocalScheduleSnapshot(for userID: String?) {
        let owner = userDefaults.string(forKey: localScheduleOwnerKey)
        let targetScope = localScheduleScope(for: userID)
        guard !isLocalScheduleBlocked(for: userID) else { return }
        guard owner == targetScope || (owner == nil && userID != nil) else { return }
        guard let data else { return }
        let snapshot = LocalScheduleSnapshot(
            classes: data.classes,
            isSecondLunch: data.isSecondLunch,
            theme: currentTheme
        )
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(encoded, forKey: localScheduleSnapshotKey(for: userID))
    }

    /// The legacy app stored the active schedule in one global file while its
    /// pending-cloud marker was UID-scoped. Switching accounts could therefore
    /// replace user A's unsynced payload with user B's data and later upload B's
    /// data into A. Keep the legacy file as the active view/widget copy, but
    /// restore its durable source from a UID-scoped snapshot on every switch.
    private func activateLocalSchedule(
        for userID: String?,
        switchToGuest: Bool = false
    ) -> Bool {
        guard var current = data else { return false }

        let targetScope = localScheduleScope(for: userID)
        let currentOwner = userDefaults.string(forKey: localScheduleOwnerKey)
        if userID == nil,
           currentOwner?.hasPrefix("user:") == true,
           !switchToGuest {
            // Firebase Auth may briefly publish nil while restoring a signed-in
            // session. Keep the known owner's active payload until a real UID
            // arrives; only a transition from a known UID is a sign-out.
            return true
        }
        // A real account/guest transition gets a fresh validation attempt. A
        // transient nil-auth startup above deliberately keeps the known user's
        // existing fence in place.
        blockedLocalScheduleScope = nil
        let snapshotKey = localScheduleSnapshotKey(for: userID)
        let encodedSnapshot = userDefaults.data(forKey: snapshotKey)
        let decodedSnapshot = encodedSnapshot.flatMap {
            try? JSONDecoder().decode(LocalScheduleSnapshot.self, from: $0)
        }

        if encodedSnapshot != nil, decodedSnapshot == nil {
            blockedLocalScheduleScope = targetScope
            // Never expose the previous account while the selected account is
            // fenced. Keep a same-account legacy active copy visible only as a
            // local recovery aid; it still cannot be persisted or uploaded.
            if currentOwner != targetScope {
                // A pre-scoped-snapshot build may have left the previous
                // account's only unsynced copy in the legacy global files.
                // Preserve that owner before privacy-blanking the selected
                // account; a later guest transition must not erase it.
                persistLocalScheduleSnapshot(for: locallyOwnedScheduleUserID())
                blockedLocalScheduleScope = targetScope
                current.classes = ScheduleData.defaultClasses
                current.isSecondLunch = [false, false]
                data = current.normalized()
                applyTheme(.defaultTheme)
            }
            cloudSyncPhase = .failed(corruptLocalScheduleMessage)
            return false
        }

        if let snapshot = decodedSnapshot {
            // Every edit is written to this scoped payload before the legacy
            // global copies. Prefer it even when the global owner matches: the
            // global file/theme/lunch fields may be partial or corrupt after an
            // interrupted write.
            current.classes = snapshot.classes
            current.isSecondLunch = snapshot.isSecondLunch
            data = current.normalized()
            applyTheme(snapshot.theme)
        } else if currentOwner == targetScope {
            // Backward compatibility for an account whose active global copy
            // predates scoped snapshots. The final write below seeds one.
        } else if currentOwner == nil || currentOwner == targetScope {
            // Backward-compatible rollout: the first authenticated UID claims
            // the existing global local payload, including any offline edit
            // created by a pre-fix build. A nil UID remains unowned so signup
            // can claim onboarding/guest data.
            persistLocalScheduleSnapshot(for: userID)
        } else {
            // Never show or merge the previous account's local payload while
            // the new account's cloud state is loading.
            current.classes = ScheduleData.defaultClasses
            current.isSecondLunch = [false, false]
            data = current.normalized()
            applyTheme(.defaultTheme)
            persistLocalScheduleSnapshot(for: userID)
        }

        if let userID {
            if currentOwner == nil {
                userDefaults.removeObject(forKey: localScheduleSnapshotKey(for: nil))
            }
            userDefaults.set(localScheduleScope(for: userID), forKey: localScheduleOwnerKey)
        } else if currentOwner != nil {
            userDefaults.set(targetScope, forKey: localScheduleOwnerKey)
        }

        overwriteClassesFile(with: data?.classes ?? [])
        persistence.saveLunchPreferenceLocally(data?.isSecondLunch ?? [false, false])
        saveThemeLocally(currentTheme)
        persistLocalScheduleSnapshot(for: userID)
        return true
    }

    private func loadLastSyncedCloudClasses(for userID: String?) -> [ClassItem] {
        guard let data = userDefaults.data(
            forKey: lastSyncedCloudClassesKey(for: userID)
        ) else { return [] }
        return (try? JSONDecoder().decode([ClassItem].self, from: data)) ?? []
    }

    private func persistLastSyncedCloudClasses() {
        guard let data = try? JSONEncoder().encode(lastSyncedCloudClasses) else { return }
        userDefaults.set(
            data,
            forKey: lastSyncedCloudClassesKey(for: pendingCloudUserID)
        )
    }

    private func recordSyncedClassesIfCurrent(
        _ fields: Set<PendingCloudField>,
        classes: [ClassItem]
    ) {
        guard fields.contains(.classes), data?.classes == classes else { return }
        lastSyncedCloudClasses = classes
        persistLastSyncedCloudClasses()
    }

    /// Three-way merge for class edits made on multiple devices. Independent
    /// edits survive; for a true same-class conflict the local edit wins. An
    /// edit racing a deletion is preserved rather than silently discarded.
    nonisolated static func mergeClasses(
        base: [ClassItem],
        local: [ClassItem],
        remote: [ClassItem]
    ) -> [ClassItem] {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedIDs = local.map(\.id) + remote.map(\.id).filter { localByID[$0] == nil }

        return orderedIDs.compactMap { id in
            let baseValue = baseByID[id]
            let localValue = localByID[id]
            let remoteValue = remoteByID[id]

            if localValue == baseValue { return remoteValue }
            if remoteValue == baseValue { return localValue }
            if localValue == remoteValue { return localValue }
            if localValue == nil { return remoteValue }
            if remoteValue == nil { return localValue }
            return localValue
        }
    }

    private func applyThemeState(_ themeState: PersistedThemeState) {
        primaryColor = Color(hex: themeState.primary)
        secondaryColor = Color(hex: themeState.secondary)
        tertiaryColor = Color(hex: themeState.tertiary)
        primaryFontChoice = themeState.primaryFontChoice
        secondaryFontChoice = themeState.secondaryFontChoice
    }

    private func applyTheme(_ theme: ThemeColors) {
        primaryColor = Color(hex: theme.primary)
        secondaryColor = Color(hex: theme.secondary)
        tertiaryColor = Color(hex: theme.tertiary)
        primaryFontChoice = theme.primaryFontChoice
        secondaryFontChoice = theme.secondaryFontChoice
    }

    private func applyScheduleState(_ scheduleState: PersistedScheduleState, overwriteClasses: Bool = true) {
        data = scheduleState.normalizedData
        applyThemeState(scheduleState.theme)
        saveThemeLocally(currentTheme)
        persistence.saveLunchPreferenceLocally(scheduleState.normalizedData.isSecondLunch)
        if overwriteClasses {
            overwriteClassesFile(with: scheduleState.normalizedData.classes)
        }
    }

    private func getDayNumber(for currentDay: String) -> Int? {
        let map = ["g1":0,"b1":1,"g2":2,"b2":3,"a1":4,"a2":5,"a3":6,"a4":7,"l1":8,"l2":9,"s1":10]
        guard let dayIndex = map[currentDay.lowercased()],
              let data,
              data.days.indices.contains(dayIndex) else { return nil }
        return dayIndex
    }

    private func parseCSV(_ csvString: String, events: [CustomEvent]) {
        guard let tempDict = CSVParser.parseScheduleCSV(csvString) else {
            output = "Failed to load schedule."
            return
        }

        scheduleDict = tempDict
        applySelectedDate(selectedDate, events: events)
        if let dictData = try? JSONEncoder().encode(tempDict) {
            SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
        }
        updateNightlyNotification()
        syncDerivedOutputs(events: events)
    }

    private func refreshRenderedSchedule(events: [CustomEvent]) {
        let key = ScheduleSelectionResolver.scheduleKey(for: selectedDate)
        let specialScheduleCode = scheduleDict?[key].flatMap { $0.count > 2 ? $0[2] : nil } ?? ""
        scheduleLines = ScheduleSelectionResolver.renderedLines(
            dayCode: dayCode,
            selectedDate: selectedDate,
            data: data,
            events: events,
            specialScheduleCode: specialScheduleCode
        )
    }

    private func fetchScheduleFromGoogleSheets(events: [CustomEvent]) {
        retryScheduleLoad(events: events)
    }

    /// Legacy caches contain only `[dayCode, note]`. For an S1 date, fetch just
    /// Sheet columns A and E for that date and merge E into the cached row.
    /// This query is much smaller than downloading the full sheet again.
    private func fetchSpecialCode(for date: Date, events: [CustomEvent]) {
        let key = ScheduleSelectionResolver.scheduleKey(for: date)
        guard specialCodeFetchKey != key else { return }

        specialCodeFetchTask?.cancel()
        specialCodeFetchKey = key
        specialCodeFetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.specialCodeFetchKey == key {
                    self.specialCodeFetchKey = nil
                }
            }

            guard var components = URLComponents(
                string: "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/gviz/tq"
            ) else { return }
            components.queryItems = [
                URLQueryItem(name: "tqx", value: "out:csv"),
                URLQueryItem(name: "gid", value: "0"),
                URLQueryItem(name: "tq", value: "select A,E where A = '\(key)'")
            ]
            guard let url = components.url else { return }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                request.cachePolicy = .reloadRevalidatingCacheData

                let (responseData, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw URLError(.badServerResponse)
                }
                guard let csv = String(data: responseData, encoding: .utf8),
                      let specialCode = CSVParser.parseSpecialCodeCSV(csv, dateKey: key),
                      var row = scheduleDict?[key] else {
                    return
                }

                while row.count < 3 { row.append("") }
                row[2] = specialCode
                scheduleDict?[key] = row

                if let dict = scheduleDict,
                   let dictData = try? JSONEncoder().encode(dict) {
                    SharedGroup.defaults.set(dictData, forKey: "ScheduleDict")
                }

                if Calendar.current.isDate(selectedDate, inSameDayAs: date) {
                    applySelectedDate(date, events: events)
                    syncDerivedOutputs(events: events)
                }
            } catch is CancellationError {
                return
            } catch {
                print("⚠️ Fifth-column fetch failed: \(error.localizedDescription)")
            }
        }
    }

    private func fetchScheduleFromGoogleSheetsAsync(events: [CustomEvent]) async {
        scheduleFetchTask?.cancel()
        await fetchWithRetry(events: events)
    }

    func retryScheduleLoad(events: [CustomEvent]) {
        scheduleFetchTask?.cancel()
        scheduleFetchTask = Task { [weak self] in
            await self?.fetchWithRetry(events: events)
        }
    }

    private func fetchWithRetry(events: [CustomEvent], maxAttempts: Int = 3) async {
        let csvURL = "https://docs.google.com/spreadsheets/d/1vrodfGZP7wNooj8VYgpNejPaLvOl8PUyg82hwWz_uU4/export?format=csv&gid=0"
        guard let url = URL(string: csvURL) else { return }

        for attempt in 1...maxAttempts {
            do {
                try Task.checkCancellation()
                scheduleRetryAttempt = attempt
                scheduleLoadError = nil

                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                request.cachePolicy = .reloadRevalidatingCacheData

                let (responseData, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw URLError(.badServerResponse)
                }
                guard let csv = String(data: responseData, encoding: .utf8) else {
                    throw URLError(.cannotDecodeContentData)
                }

                scheduleRetryAttempt = 0
                scheduleLoadError = nil
                parseCSV(csv, events: events)
                return
            } catch is CancellationError {
                scheduleRetryAttempt = 0
                return
            } catch {
                guard attempt < maxAttempts else {
                    scheduleRetryAttempt = 0
                    scheduleLoadError = scheduleDict == nil
                        ? "Couldn’t load the schedule. Check your connection and try again."
                        : "Couldn’t refresh. Showing the last saved schedule."
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                } catch {
                    scheduleRetryAttempt = 0
                    return
                }
            }
        }
    }

    private func loadCachedSchedule(events: [CustomEvent]) {
        guard scheduleDict == nil,
              let cachedData = SharedGroup.defaults.data(forKey: "ScheduleDict"),
              let cachedSchedule = try? JSONDecoder().decode([String: [String]].self, from: cachedData) else {
            return
        }
        scheduleDict = cachedSchedule
        applySelectedDate(selectedDate, events: events)
    }

    private func saveDataForWidget(reloadTimeline: Bool = true) {
        WidgetManager.shared.saveData(
            scheduleDict: scheduleDict,
            data: data,
            dayCode: dayCode,
            reloadTimeline: reloadTimeline
        )
    }

    private func saveScheduleLinesWithEvents(
        events: [CustomEvent],
        reloadTimeline: Bool = true
    ) {
        WidgetManager.shared.saveScheduleLinesWithEvents(
            scheduleLines: scheduleLines,
            events: events,
            dayCode: dayCode,
            selectedDate: selectedDate,
            reloadTimeline: reloadTimeline
        )
    }

    private func updateLiveActivity() {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let dayName = getDayInfo(for: dayCode)?.name ?? dayCode
        WidgetManager.shared.updateLiveActivity(
            scheduleLines: scheduleLines,
            dayCode: dayCode,
            dayName: dayName,
            isToday: isToday
        )
    }
}
