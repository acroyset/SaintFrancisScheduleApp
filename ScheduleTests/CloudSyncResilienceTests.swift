import XCTest
import SwiftUI
@testable import Schedule

@MainActor
final class CloudSyncResilienceTests: XCTestCase {
    private enum TestFailure: Error {
        case offline
        case corruptedPayload
        case rejectedWrite
    }

    func testPartialV4DocumentIsNotTreatedAsFullyMigrated() {
        let partial: [String: Any] = [
            "encrypted": [
                "schemaVersion": 4,
                "schedule": "schedule",
                "theme": "theme",
                "isSecondLunch": "lunch"
            ]
        ]
        let complete: [String: Any] = [
            "encrypted": [
                "schemaVersion": 4,
                "schedule": "schedule",
                "theme": "theme",
                "isSecondLunch": "lunch",
                "events": "events"
            ]
        ]

        XCTAssertFalse(DataManager.isCanonicalUserDocument(partial))
        XCTAssertTrue(DataManager.isCanonicalUserDocument(complete))
    }

    func testMigrationNeverOverwritesNewerCanonicalDeviceWrites() {
        let candidate: [String: Any] = [
            "uid": "user",
            "privacyPolicy": "old-policy",
            "encrypted": [
                "schemaVersion": 4,
                "schedule": "old-schedule",
                "theme": "old-theme",
                "isSecondLunch": "old-lunch",
                "events": "old-events"
            ]
        ]
        let latest: [String: Any] = [
            "uid": "user",
            "privacyPolicy": "new-policy",
            "encrypted": [
                "schedule": "newer-device-schedule",
                "events": "newer-device-events"
            ]
        ]

        let merged = DataManager.migrationWriteData(
            candidate: candidate,
            latestRoot: latest
        )
        let encrypted = merged["encrypted"] as? [String: Any]

        XCTAssertEqual(encrypted?["schedule"] as? String, "newer-device-schedule")
        XCTAssertEqual(encrypted?["events"] as? String, "newer-device-events")
        XCTAssertEqual(encrypted?["theme"] as? String, "old-theme")
        XCTAssertEqual(merged["privacyPolicy"] as? String, "new-policy")
    }

    func testPartialV4MigrationFillsMissingFieldsWithoutReplacingExistingData() {
        let filled = DataManager.fillingMissingEncryptedFields(
            existing: [
                "schemaVersion": 4,
                "schedule": "existing-schedule",
                "events": "existing-events"
            ],
            fallback: [
                "schedule": "fallback-schedule",
                "theme": "fallback-theme",
                "isSecondLunch": "fallback-lunch",
                "events": "fallback-events"
            ]
        )

        XCTAssertEqual(filled["schedule"] as? String, "existing-schedule")
        XCTAssertEqual(filled["events"] as? String, "existing-events")
        XCTAssertEqual(filled["theme"] as? String, "fallback-theme")
        XCTAssertEqual(filled["isSecondLunch"] as? String, "fallback-lunch")
    }

    func testTwoDevicesEditingDifferentClassesMergeWithoutDataLoss() {
        let firstID = UUID()
        let secondID = UUID()
        let base = [
            ClassItem(id: firstID, name: "Math", teacher: "A", room: "1"),
            ClassItem(id: secondID, name: "English", teacher: "B", room: "2")
        ]
        var local = base
        local[0].room = "101"
        var remote = base
        remote[1].teacher = "Remote Teacher"

        let merged = GlobalDataStore.mergeClasses(
            base: base,
            local: local,
            remote: remote
        )

        XCTAssertEqual(merged[0].room, "101")
        XCTAssertEqual(merged[1].teacher, "Remote Teacher")
    }

    func testClassDeletionRacingAnEditPreservesTheEdit() {
        let original = ClassItem(name: "Math", teacher: "A", room: "1")
        var edited = original
        edited.room = "101"

        XCTAssertEqual(
            GlobalDataStore.mergeClasses(
                base: [original],
                local: [],
                remote: [edited]
            ),
            [edited]
        )
    }

    func testMigrationCombinesSyncStateAndRootWithoutDroppingEither() {
        let merged = DataManager.mergedLegacyUserData(
            oldState: [
                "classes": "state-classes",
                "customEvents": "state-events"
            ],
            userRoot: [
                "classes": "newer-root-classes",
                "privacyPolicy": "accepted"
            ]
        )

        XCTAssertEqual(merged["classes"] as? String, "newer-root-classes")
        XCTAssertEqual(merged["customEvents"] as? String, "state-events")
        XCTAssertEqual(merged["privacyPolicy"] as? String, "accepted")
    }

    func testFlakyScheduleReadRetriesAndAppliesRemoteWithoutWriting() async throws {
        let context = try makeScheduleContext(loadRetryDelays: [.milliseconds(5), .milliseconds(5)])
        let local = schedule(named: "Local", secondLunch: [true, false])
        let remote = schedule(named: "Remote", secondLunch: [false, true])
        context.cloud.loadSteps = [
            .failure(TestFailure.offline),
            .failure(TestFailure.offline),
            .success(scheduleState(remote))
        ]
        context.store.data = local

        context.store.handleUserChange(context.userID, authManager: context.auth)

        await assertEventually {
            context.cloud.loadAttempts.count == 3
                && context.store.data?.classes.first?.name == "Remote"
        }
        XCTAssertEqual(context.store.data?.isSecondLunch, [false, true])
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
    }

    func testScheduleEditWhileOfflineWaitsForReadThenUploadsLocalChange() async throws {
        let context = try makeScheduleContext(loadRetryDelays: [.milliseconds(40)])
        let local = schedule(named: "Local", secondLunch: [false, false])
        let remote = schedule(named: "Remote", secondLunch: [false, true])
        context.cloud.loadSteps = [
            .failure(TestFailure.offline),
            .success(scheduleState(remote))
        ]
        context.store.data = local
        context.store.handleUserChange(context.userID, authManager: context.auth)

        var edited = local
        edited.classes[0].name = "Edited Offline"
        context.store.updateSchedule(edited, authManager: context.auth)

        try? await Task.sleep(for: .milliseconds(15))
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
        XCTAssertEqual(context.store.data?.classes[0].name, "Edited Offline")

        await assertEventually {
            context.cloud.saveAttempts.count == 1
        }
        XCTAssertEqual(context.cloud.saveAttempts[0].classes[0].name, "Edited Offline")
        XCTAssertEqual(context.cloud.saveAttempts[0].isSecondLunch, [false, true])
    }

    func testEmptyCloudSchedulePreservesAllLocalFields() async throws {
        let context = try makeScheduleContext()
        let localTheme = ThemeColors(
            primary: "#AA0000FF",
            secondary: "#00AA00FF",
            tertiary: "#000000FF",
            primaryFont: .serif,
            secondaryFont: .monospaced
        )
        let local = schedule(named: "Local Only", secondLunch: [true, true])
        let emptyCloud = PersistedScheduleState(
            classes: [],
            days: local.days,
            isSecondLunch: [false, false],
            theme: PersistedThemeState(theme: .defaultTheme),
            isAuthoritative: false
        )
        context.cloud.loadSteps = [.success(emptyCloud)]
        context.store.data = local
        apply(localTheme, to: context.store)

        context.store.handleUserChange(context.userID, authManager: context.auth)

        await assertEventually { context.cloud.loadAttempts.count == 1 }
        XCTAssertEqual(context.store.data?.classes[0].name, "Local Only")
        XCTAssertEqual(context.store.data?.isSecondLunch, [true, true])
        XCTAssertEqual(context.store.currentTheme, localTheme)
        await assertEventually { context.cloud.saveAttempts.count == 1 }
        XCTAssertEqual(context.cloud.saveAttempts[0].classes[0].name, "Local Only")
        XCTAssertEqual(context.cloud.saveAttempts[0].isSecondLunch, [true, true])
        XCTAssertEqual(context.cloud.saveAttempts[0].theme, localTheme)
    }

    func testAuthoritativeEmptyCloudScheduleDeletesLocalValues() async throws {
        let context = try makeScheduleContext()
        let localTheme = ThemeColors(
            primary: "#AA0000FF",
            secondary: "#00AA00FF",
            tertiary: "#000000FF"
        )
        let local = schedule(named: "Must Be Deleted", secondLunch: [true, true])
        let emptyCloud = PersistedScheduleState(
            classes: [],
            days: local.days,
            isSecondLunch: [false, false],
            theme: PersistedThemeState(theme: .defaultTheme),
            isAuthoritative: true
        )
        context.cloud.loadSteps = [.success(emptyCloud)]
        context.store.data = local
        apply(localTheme, to: context.store)

        context.store.handleUserChange(context.userID, authManager: context.auth)

        await assertEventually { context.cloud.loadAttempts.count == 1 }
        XCTAssertNotEqual(context.store.data?.classes[0].name, "Must Be Deleted")
        XCTAssertEqual(context.store.data?.isSecondLunch, [false, false])
        XCTAssertEqual(context.store.currentTheme, .defaultTheme)
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
    }

    func testFailedScheduleUploadRetriesAndClearsAfterSuccess() async throws {
        let context = try makeScheduleContext(saveRetryDelay: .milliseconds(8))
        let remote = schedule(named: "Remote", secondLunch: [false, false])
        context.cloud.loadSteps = [.success(scheduleState(remote))]
        context.cloud.saveResults = [
            .failure(TestFailure.rejectedWrite),
            .success(())
        ]
        context.store.data = remote
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        var edited = remote
        edited.isSecondLunch = [true, false]
        context.store.updateSchedule(edited, authManager: context.auth)

        await assertEventually { context.cloud.saveAttempts.count == 2 }
        XCTAssertEqual(context.cloud.saveAttempts.map(\.isSecondLunch), [
            [true, false],
            [true, false]
        ])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(context.cloud.saveAttempts.count, 2)
    }

    func testRapidScheduleEditsCoalesceIntoOneUpload() async throws {
        let context = try makeScheduleContext(saveDebounce: .milliseconds(30))
        let remote = schedule(named: "Remote", secondLunch: [false, false])
        context.cloud.loadSteps = [.success(scheduleState(remote))]
        context.store.data = remote
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        for name in ["A", "AB", "ABC"] {
            var edited = context.store.data ?? remote
            edited.classes[0].name = name
            context.store.updateSchedule(edited, authManager: context.auth)
        }

        await assertEventually { context.cloud.saveAttempts.count == 1 }
        XCTAssertEqual(context.cloud.saveAttempts[0].classes[0].name, "ABC")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(context.cloud.saveAttempts.count, 1)
    }

    func testExplicitScheduleSaveUploadsCurrentClassesEvenWithoutDetectedDiff() async throws {
        let context = try makeScheduleContext()
        let current = schedule(named: "Edited Class", secondLunch: [false, false])
        context.cloud.loadSteps = [.success(scheduleState(current))]
        context.store.data = current
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        context.store.saveSchedule(authManager: context.auth)

        await assertEventually { context.cloud.saveAttempts.count == 1 }
        XCTAssertEqual(context.cloud.saveAttempts[0].classes[0].name, "Edited Class")
    }

    func testManualScheduleSyncReportsOfflineAndKeepsChangesPending() async throws {
        let connectivity = TestCloudConnectivity(isConnected: true)
        let context = try makeScheduleContext(connectivity: connectivity)
        let current = schedule(named: "Offline Class", secondLunch: [false, false])
        context.cloud.loadSteps = [.success(scheduleState(current))]
        context.store.data = current
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        connectivity.isConnected = false
        context.store.saveSchedule(authManager: context.auth)
        context.store.retryCloudSync(authManager: context.auth, force: true)

        guard case .failed(let message) = context.store.cloudSyncPhase else {
            return XCTFail("Offline sync should report a failure")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("internet"))
        XCTAssertGreaterThan(context.store.pendingCloudChangeCount, 0)
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
    }

    func testPullRefreshLoadsLatestCloudScheduleWithoutWritingUnchangedLocalData() async throws {
        let context = try makeScheduleContext()
        let initial = schedule(named: "Initial", secondLunch: [false, false])
        let latest = schedule(named: "Latest Device", secondLunch: [true, false])
        context.cloud.loadSteps = [
            .success(scheduleState(initial)),
            .success(scheduleState(latest))
        ]
        context.store.data = initial
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        await context.store.refreshCloudSync(authManager: context.auth)

        XCTAssertEqual(context.store.data?.classes[0].name, "Latest Device")
        XCTAssertEqual(context.store.data?.isSecondLunch, [true, false])
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
    }

    func testScheduleAccountSwitchIgnoresStaleLoadAndStartsNewLoad() async throws {
        let context = try makeScheduleContext()
        let firstUserID = context.userID
        let secondUserID = "second-\(UUID().uuidString)"
        context.cloud.loadSteps = [
            .success(scheduleState(schedule(named: "First Account", secondLunch: [true, false])), delay: .milliseconds(50)),
            .success(scheduleState(schedule(named: "Second Account", secondLunch: [false, true])))
        ]
        context.store.data = schedule(named: "Local", secondLunch: [false, false])
        context.store.handleUserChange(firstUserID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts == [firstUserID] }

        context.auth.user = User(id: secondUserID, email: "second@example.com")
        context.store.handleUserChange(secondUserID, authManager: context.auth)

        await assertEventually {
            context.cloud.loadAttempts.contains(secondUserID)
                && context.store.data?.classes[0].name == "Second Account"
        }
        try? await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(context.store.data?.classes[0].name, "Second Account")
        XCTAssertEqual(context.store.data?.isSecondLunch, [false, true])
    }

    func testPendingScheduleEditRemainsScopedAcrossRoundTripAccountSwitch() async throws {
        let suiteName = "CloudSyncScheduleAccountScope.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUserID = "schedule-first-\(UUID().uuidString)"
        let secondUserID = "schedule-second-\(UUID().uuidString)"
        let auth = makeAuth(userID: firstUserID)
        let cloud = ScriptedScheduleCloud()
        let store = makeScheduleStore(
            defaults: defaults,
            cloud: cloud,
            loadRetryDelays: []
        )
        let firstLocal = schedule(named: "First Local", secondLunch: [true, false])
        let secondRemote = schedule(named: "Second Remote", secondLunch: [false, true])
        let firstRemote = schedule(named: "First Remote", secondLunch: [false, false])
        cloud.loadSteps = [
            .failure(TestFailure.offline),
            .failure(TestFailure.offline),
            .success(scheduleState(secondRemote)),
            .success(scheduleState(firstRemote))
        ]

        store.data = firstLocal
        store.handleUserChange(firstUserID, authManager: auth)
        await assertEventually { cloud.loadAttempts == [firstUserID] }

        var firstOfflineEdit = firstLocal
        firstOfflineEdit.classes[0].name = "First Offline Edit"
        firstOfflineEdit.isSecondLunch = [true, true]
        store.updateSchedule(firstOfflineEdit, authManager: auth)
        await assertEventually {
            cloud.loadAttempts.filter { $0 == firstUserID }.count == 2
        }

        auth.user = User(id: secondUserID, email: "second@example.com")
        store.handleUserChange(secondUserID, authManager: auth)
        let loadedSecondSchedule = await waitUntil {
            cloud.loadAttempts.contains(secondUserID)
                && store.data?.classes[0].name == "Second Remote"
        }
        XCTAssertTrue(
            loadedSecondSchedule,
            "attempts=\(cloud.loadAttempts), active=\(store.data?.classes.first?.name ?? "nil")"
        )

        auth.user = User(id: firstUserID, email: "first@example.com")
        store.handleUserChange(firstUserID, authManager: auth)
        let reloadedFirstSchedule = await waitUntil {
            cloud.loadAttempts.filter { $0 == firstUserID }.count == 3
                && cloud.saveAttempts.contains { $0.userID == firstUserID }
        }
        XCTAssertTrue(
            reloadedFirstSchedule,
            "loads=\(cloud.loadAttempts), saves=\(cloud.saveAttempts.map(\.userID))"
        )

        XCTAssertEqual(store.data?.classes[0].name, "First Offline Edit")
        XCTAssertEqual(store.data?.isSecondLunch, [true, true])
        let firstUserSave = try XCTUnwrap(
            cloud.saveAttempts.last { $0.userID == firstUserID }
        )
        XCTAssertEqual(firstUserSave.classes[0].name, "First Offline Edit")
        XCTAssertFalse(firstUserSave.classes.contains { $0.name == "Second Remote" })
    }

    func testTransientNilAuthKeepsOwnedScheduleAndUploadsPreRestoreEdit() async throws {
        let suiteName = "CloudSyncScheduleAuthRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "schedule-auth-restore-\(UUID().uuidString)"
        let auth = makeAuth(userID: userID)
        let initial = schedule(named: "Owned Before Relaunch", secondLunch: [false, false])

        let firstCloud = ScriptedScheduleCloud()
        firstCloud.loadSteps = [.failure(TestFailure.offline)]
        let firstStore = makeScheduleStore(
            defaults: defaults,
            cloud: firstCloud,
            loadRetryDelays: []
        )
        firstStore.data = initial
        firstStore.handleUserChange(userID, authManager: auth)
        await assertEventually { firstCloud.loadAttempts.count == 1 }

        auth.user = nil
        let recoveredCloud = ScriptedScheduleCloud()
        recoveredCloud.loadSteps = [
            .success(scheduleState(schedule(named: "Remote", secondLunch: [false, true])))
        ]
        let relaunchedStore = makeScheduleStore(defaults: defaults, cloud: recoveredCloud)
        relaunchedStore.data = initial
        relaunchedStore.handleUserChange(nil, authManager: auth)

        var editedBeforeAuthRestored = initial
        editedBeforeAuthRestored.classes[0].name = "Edit During Auth Restore"
        relaunchedStore.updateSchedule(editedBeforeAuthRestored, authManager: auth)
        XCTAssertEqual(relaunchedStore.data?.classes[0].name, "Edit During Auth Restore")

        auth.user = User(id: userID, email: "test@example.com")
        relaunchedStore.handleUserChange(userID, authManager: auth)

        await assertEventually { recoveredCloud.saveAttempts.count == 1 }
        XCTAssertEqual(relaunchedStore.data?.classes[0].name, "Edit During Auth Restore")
        XCTAssertEqual(
            recoveredCloud.saveAttempts[0].classes[0].name,
            "Edit During Auth Restore"
        )
    }

    func testScheduleRelaunchRestoresPendingScopedSnapshotWhenLegacyActiveCopyIsDamaged() async throws {
        let suiteName = "CloudSyncScheduleDamagedActive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "schedule-damaged-active-\(UUID().uuidString)"
        let auth = makeAuth(userID: userID)
        let base = schedule(named: "Cloud Baseline", secondLunch: [false, false])
        defaults.set(
            try JSONEncoder().encode(base.classes),
            forKey: "LastSyncedCloudClasses.\(userID)"
        )

        let offlineCloud = ScriptedScheduleCloud()
        let offlineStore = makeScheduleStore(
            defaults: defaults,
            cloud: offlineCloud,
            loadRetryDelays: [],
            connectivity: TestCloudConnectivity(isConnected: false)
        )
        offlineStore.data = base
        offlineStore.handleUserChange(userID, authManager: auth)

        var pending = base
        pending.classes[0].name = "Pending Survives Damage"
        pending.isSecondLunch = [true, true]
        offlineStore.updateSchedule(pending, authManager: auth)
        XCTAssertNotNil(defaults.data(forKey: "LocalScheduleSnapshot.\(userID)"))

        // Model a relaunch after the legacy Classes.txt/lunch copies were
        // partially written. The UID snapshot above is complete and pending.
        let recoveredCloud = ScriptedScheduleCloud()
        recoveredCloud.loadSteps = [.success(scheduleState(base))]
        let relaunchedStore = makeScheduleStore(
            defaults: defaults,
            cloud: recoveredCloud,
            loadRetryDelays: [],
            saveDebounce: .milliseconds(5)
        )
        relaunchedStore.data = ScheduleData(
            classes: [],
            days: base.days,
            isSecondLunch: [false, false]
        ).normalized()
        relaunchedStore.handleUserChange(userID, authManager: auth)

        await assertEventually { recoveredCloud.saveAttempts.count == 1 }
        XCTAssertEqual(relaunchedStore.data?.classes[0].name, "Pending Survives Damage")
        XCTAssertEqual(relaunchedStore.data?.isSecondLunch, [true, true])
        XCTAssertEqual(
            recoveredCloud.saveAttempts[0].classes[0].name,
            "Pending Survives Damage"
        )
        XCTAssertEqual(recoveredCloud.saveAttempts[0].isSecondLunch, [true, true])
    }

    func testCorruptScopedScheduleSnapshotFailsClosedWithoutCloudWrite() async throws {
        let suiteName = "CloudSyncScheduleCorruptLocal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "schedule-corrupt-local-\(UUID().uuidString)"
        let otherUserID = "schedule-other-\(UUID().uuidString)"
        let corrupt = Data([0x00, 0xFF, 0x01, 0xFE])
        defaults.set("user:\(otherUserID)", forKey: "LocalScheduleOwner")
        defaults.set(corrupt, forKey: "LocalScheduleSnapshot.\(userID)")

        let cloud = ScriptedScheduleCloud()
        cloud.loadSteps = [
            .success(scheduleState(schedule(named: "Cloud Must Stay Untouched", secondLunch: [false, false])))
        ]
        let store = makeScheduleStore(defaults: defaults, cloud: cloud)
        store.data = schedule(named: "Other Account", secondLunch: [true, true])
        let auth = makeAuth(userID: userID)

        store.handleUserChange(userID, authManager: auth)
        store.retryCloudSync(authManager: auth, force: true)
        var blockedEdit = try XCTUnwrap(store.data)
        blockedEdit.classes[0].name = "Blocked Target Edit"
        store.updateSchedule(blockedEdit, authManager: auth)
        store.retryCloudSync(authManager: auth, force: true)
        await store.flushCloudSync(authManager: auth)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(cloud.loadAttempts.isEmpty)
        XCTAssertTrue(cloud.saveAttempts.isEmpty)
        XCTAssertNotEqual(store.data?.classes[0].name, "Other Account")
        XCTAssertNotEqual(store.data?.classes[0].name, "Blocked Target Edit")
        XCTAssertEqual(
            defaults.string(forKey: "LocalScheduleOwner"),
            "user:\(otherUserID)"
        )
        XCTAssertNotNil(
            defaults.data(forKey: "LocalScheduleSnapshot.\(otherUserID)")
        )
        XCTAssertEqual(
            defaults.data(forKey: "LocalScheduleSnapshot.\(userID)"),
            corrupt
        )
        guard case .failed = store.cloudSyncPhase else {
            return XCTFail("Corrupt local schedule must fence cloud sync")
        }
    }

    func testSameOwnerCorruptScheduleSnapshotFencesPreactivationEditAndRetry() async throws {
        let suiteName = "CloudSyncScheduleSameOwnerCorrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "schedule-same-owner-corrupt-\(UUID().uuidString)"
        let corrupt = Data([0x00, 0xFF, 0x01, 0xFE])
        let baseline = schedule(named: "Remote Baseline", secondLunch: [false, false])
        let encodedBaseline = try JSONEncoder().encode(baseline.classes)
        defaults.set("user:\(userID)", forKey: "LocalScheduleOwner")
        defaults.set(corrupt, forKey: "LocalScheduleSnapshot.\(userID)")
        defaults.set(["classes"], forKey: "PendingCloudScheduleFields.\(userID)")
        defaults.set(encodedBaseline, forKey: "LastSyncedCloudClasses.\(userID)")

        let cloud = ScriptedScheduleCloud()
        cloud.loadSteps = [.success(scheduleState(baseline))]
        let store = makeScheduleStore(defaults: defaults, cloud: cloud)
        let recoveryCopy = schedule(named: "Same Owner Recovery", secondLunch: [true, false])
        store.data = recoveryCopy
        let auth = makeAuth(userID: userID)

        var preactivationEdit = recoveryCopy
        preactivationEdit.classes[0].name = "Preactivation Bypass"
        store.updateSchedule(preactivationEdit, authManager: auth)
        store.handleUserChange(userID, authManager: auth)
        store.retryCloudSync(authManager: auth, force: true)

        var postactivationEdit = try XCTUnwrap(store.data)
        postactivationEdit.classes[0].name = "Postactivation Bypass"
        store.updateSchedule(postactivationEdit, authManager: auth)
        await store.flushCloudSync(authManager: auth)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(cloud.loadAttempts.isEmpty)
        XCTAssertTrue(cloud.saveAttempts.isEmpty)
        XCTAssertEqual(store.data?.classes[0].name, "Same Owner Recovery")
        XCTAssertEqual(
            defaults.data(forKey: "LocalScheduleSnapshot.\(userID)"),
            corrupt
        )
        XCTAssertEqual(
            Set(defaults.stringArray(forKey: "PendingCloudScheduleFields.\(userID)") ?? []),
            Set(["classes"])
        )
        XCTAssertEqual(
            defaults.data(forKey: "LastSyncedCloudClasses.\(userID)"),
            encodedBaseline
        )
        guard case .failed = store.cloudSyncPhase else {
            return XCTFail("Same-owner corrupt schedule must keep its durable fence")
        }
    }

    func testExhaustedScheduleReadsKeepLocalDataAndManualRetryRecovers() async throws {
        let context = try makeScheduleContext(
            loadRetryDelays: [.milliseconds(4), .milliseconds(4), .milliseconds(4)]
        )
        let local = schedule(named: "Safe Local", secondLunch: [true, false])
        let recovered = schedule(named: "Recovered", secondLunch: [false, true])
        context.cloud.loadSteps = [
            .failure(TestFailure.offline),
            .failure(TestFailure.offline),
            .failure(TestFailure.corruptedPayload),
            .failure(TestFailure.offline),
            .success(scheduleState(recovered))
        ]
        context.store.data = local
        context.store.handleUserChange(context.userID, authManager: context.auth)

        await assertEventually { context.cloud.loadAttempts.count == 4 }
        XCTAssertEqual(context.store.data?.classes[0].name, "Safe Local")
        XCTAssertEqual(context.store.data?.isSecondLunch, [true, false])
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)

        context.store.retryCloudSync(authManager: context.auth)
        await assertEventually {
            context.cloud.loadAttempts.count == 5
                && context.store.data?.classes[0].name == "Recovered"
        }
    }

    func testPendingScheduleEditSurvivesStoreRecreation() async throws {
        let suiteName = "CloudSyncResilienceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "schedule-persist-\(UUID().uuidString)"
        let auth = makeAuth(userID: userID)
        let local = schedule(named: "Local", secondLunch: [true, false])

        let offlineCloud = ScriptedScheduleCloud()
        offlineCloud.loadSteps = [.failure(TestFailure.offline)]
        let firstStore = makeScheduleStore(
            defaults: defaults,
            cloud: offlineCloud,
            loadRetryDelays: []
        )
        firstStore.data = local
        firstStore.handleUserChange(userID, authManager: auth)
        var edited = local
        edited.isSecondLunch = [true, true]
        firstStore.updateSchedule(edited, authManager: auth)
        await assertEventually { offlineCloud.loadAttempts.count == 1 }
        XCTAssertTrue(offlineCloud.saveAttempts.isEmpty)

        auth.user = nil
        firstStore.handleUserChange(nil, authManager: auth)

        let recoveredCloud = ScriptedScheduleCloud()
        let remote = schedule(named: "Remote", secondLunch: [false, false])
        recoveredCloud.loadSteps = [.success(scheduleState(remote))]
        let secondStore = makeScheduleStore(defaults: defaults, cloud: recoveredCloud)
        secondStore.data = edited
        auth.user = User(id: userID, email: "test@example.com")
        secondStore.handleUserChange(userID, authManager: auth)

        await assertEventually { recoveredCloud.saveAttempts.count == 1 }
        XCTAssertEqual(secondStore.data?.classes[0].name, "Remote")
        XCTAssertEqual(secondStore.data?.isSecondLunch, [true, true])
        XCTAssertEqual(recoveredCloud.saveAttempts[0].isSecondLunch, [true, true])
    }

    func testFlakyEventsReadRetriesAndAppliesRemoteWithoutWriting() async throws {
        let context = try makeEventsContext(loadRetryDelays: [.milliseconds(5), .milliseconds(5)])
        let remote = event(title: "Remote Event")
        context.cloud.loadSteps = [
            .failure(TestFailure.offline),
            .failure(TestFailure.corruptedPayload),
            .success([remote])
        ]

        context.manager.handleUserChange(using: context.auth)

        await assertEventually {
            context.cloud.loadAttempts.count == 3
                && context.manager.events == [remote]
        }
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
    }

    func testOfflineEventEditWaitsForReadAndFailedWriteRetries() async throws {
        let context = try makeEventsContext(
            loadRetryDelays: [.milliseconds(35)],
            saveRetryDelay: .milliseconds(8)
        )
        let local = event(title: "Offline Event")
        context.cloud.loadSteps = [
            .failure(TestFailure.offline),
            .success([event(title: "Remote Event")])
        ]
        context.cloud.saveResults = [
            .failure(TestFailure.rejectedWrite),
            .success(())
        ]
        context.manager.handleUserChange(using: context.auth)
        context.manager.addEvent(local)

        try? await Task.sleep(for: .milliseconds(12))
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
        XCTAssertEqual(context.manager.events, [local])

        await assertEventually { context.cloud.saveAttempts.count == 2 }
        let expectedTitles = Set(["Offline Event", "Remote Event"])
        XCTAssertEqual(Set(context.manager.events.map(\.title)), expectedTitles)
        XCTAssertEqual(
            Set(context.cloud.saveAttempts[0].events.map(\.title)),
            expectedTitles
        )
        XCTAssertEqual(
            Set(context.cloud.saveAttempts[1].events.map(\.title)),
            expectedTitles
        )
    }

    func testRapidEventEditsCoalesceIntoOneUpload() async throws {
        let context = try makeEventsContext(saveDebounce: .milliseconds(30))
        context.cloud.loadSteps = [.success([])]
        context.manager.handleUserChange(using: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        context.manager.addEvent(event(title: "One"))
        context.manager.addEvent(event(title: "Two"))
        context.manager.addEvent(event(title: "Three"))

        await assertEventually { context.cloud.saveAttempts.count == 1 }
        XCTAssertEqual(context.cloud.saveAttempts[0].events.map(\.title), ["One", "Two", "Three"])
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(context.cloud.saveAttempts.count, 1)
    }

    func testFirstEmptyCloudBaselinePreservesAndUploadsLocalEvents() async throws {
        let context = try makeEventsContext(saveDebounce: .milliseconds(40))
        let local = event(title: "Local Before First Sync")
        context.manager.events = [local]
        context.manager.saveEvents(syncToCloud: false)
        context.cloud.loadSteps = [.success([])]

        context.manager.handleUserChange(using: context.auth)

        await assertEventually {
            context.defaults.bool(
                forKey: "PendingCloudEvents.\(context.userID)"
            ) && context.defaults.bool(
                forKey: "EstablishedCloudEventsBaseline.\(context.userID)"
            )
        }
        context.cloud.emit([])
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(context.manager.events, [local])
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)

        await assertEventually { context.cloud.saveAttempts.count == 1 }
        XCTAssertEqual(context.manager.events, [local])
        XCTAssertEqual(context.cloud.saveAttempts[0].events, [local])
        XCTAssertTrue(
            context.defaults.bool(
                forKey: "EstablishedCloudEventsBaseline.\(context.userID)"
            )
        )
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(context.cloud.saveAttempts.count, 1)
    }

    func testMissingRootScheduleStateIsEmptyNonAuthoritativeAndClearsRootCache() {
        let userID = "missing-schedule-\(UUID().uuidString)"
        DataManager.cacheValidatedRoot(["stale": true], for: userID)
        XCTAssertNotNil(DataManager.recentValidatedRootData(for: userID))

        let state = DataManager.scheduleStateForMissingRoot(for: userID)

        XCTAssertTrue(state.0.isEmpty)
        XCTAssertEqual(state.1, .defaultTheme)
        XCTAssertEqual(state.2, [false, false])
        XCTAssertFalse(state.3)
        XCTAssertNil(DataManager.recentValidatedRootData(for: userID))
    }

    func testMissingRootEventsStateIsExplicitEmptyAndClearsSharedRootCache() {
        let userID = "missing-events-\(UUID().uuidString)"
        DataManager.cacheValidatedRoot(["stale": true], for: userID)
        XCTAssertNotNil(DataManager.recentValidatedRootData(for: userID))

        XCTAssertTrue(CloudEventsDataManager.eventsForMissingRoot(for: userID).isEmpty)
        XCTAssertNil(DataManager.recentValidatedRootData(for: userID))
    }

    func testMissingEventRootPreservesEstablishedLocalEventsAndQueuesRecovery() async throws {
        let context = try makeEventsContext()
        let local = event(title: "Recover After Missing Root")
        context.manager.events = [local]
        context.manager.saveEvents(syncToCloud: false)
        context.defaults.set(
            try JSONEncoder().encode([local]),
            forKey: "LastSyncedCloudEvents.\(context.userID)"
        )
        context.defaults.set(
            true,
            forKey: "EstablishedCloudEventsBaseline.\(context.userID)"
        )
        context.cloud.loadSteps = [
            .success([], isAuthoritative: false)
        ]

        context.manager.handleUserChange(using: context.auth)

        await assertEventually {
            context.cloud.loadAttempts.count == 1
                && context.cloud.saveAttempts.count == 1
        }
        XCTAssertEqual(context.manager.events, [local])
        XCTAssertEqual(context.cloud.saveAttempts[0].events, [local])
        XCTAssertTrue(
            context.defaults.bool(forKey: "EstablishedCloudEventsBaseline.\(context.userID)")
        )
    }

    func testManualLoadHonorsAuthoritativeEmptyDeletesAndOnlyFallsBackWhenMissing() {
        let localEvent = event(title: "Stale Local Event")
        XCTAssertEqual(
            CloudService.resolveLoadedEvents(
                local: [localEvent],
                cloud: PersistedEventsState(events: [], isAuthoritative: true)
            ),
            []
        )
        XCTAssertEqual(
            CloudService.resolveLoadedEvents(
                local: [localEvent],
                cloud: PersistedEventsState(events: [], isAuthoritative: false)
            ),
            [localEvent]
        )

        let localSchedule = scheduleState(
            schedule(named: "Stale Local Class", secondLunch: [true, true])
        )
        let authoritativeEmpty = PersistedScheduleState(
            classes: [],
            days: localSchedule.days,
            isSecondLunch: [false, false],
            theme: PersistedThemeState(theme: .defaultTheme),
            isAuthoritative: true
        )
        let missingSchedule = PersistedScheduleState(
            classes: [],
            days: localSchedule.days,
            isSecondLunch: [false, false],
            theme: PersistedThemeState(theme: .defaultTheme),
            isAuthoritative: false
        )

        XCTAssertFalse(
            CloudService.resolveLoadedSchedule(
                local: localSchedule,
                cloud: authoritativeEmpty
            ).classes.contains { $0.name == "Stale Local Class" }
        )
        XCTAssertTrue(
            CloudService.resolveLoadedSchedule(
                local: localSchedule,
                cloud: missingSchedule
            ).classes.contains { $0.name == "Stale Local Class" }
        )
    }

    func testPersistedLastSyncedKeyMakesInitialEmptyCloudAuthoritative() async throws {
        let context = try makeEventsContext()
        let local = event(title: "Previously Synced")
        context.manager.events = [local]
        context.manager.saveEvents(syncToCloud: false)
        context.defaults.set(
            try JSONEncoder().encode([CustomEvent]()),
            forKey: "LastSyncedCloudEvents.\(context.userID)"
        )
        context.cloud.loadSteps = [.success([])]

        context.manager.handleUserChange(using: context.auth)

        await assertEventually {
            context.cloud.loadAttempts.count == 1 && context.manager.events.isEmpty
        }
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
        XCTAssertTrue(
            context.defaults.bool(
                forKey: "EstablishedCloudEventsBaseline.\(context.userID)"
            )
        )
        let persisted = try XCTUnwrap(context.defaults.data(forKey: "CustomEvents"))
        XCTAssertEqual(try JSONDecoder().decode([CustomEvent].self, from: persisted), [])
    }

    func testEventAccountSwitchIgnoresStaleLoadAndStartsNewLoad() async throws {
        let context = try makeEventsContext()
        let firstUserID = context.userID
        let secondUserID = "events-second-\(UUID().uuidString)"
        context.cloud.loadSteps = [
            .success([event(title: "First Account")], delay: .milliseconds(50)),
            .success([event(title: "Second Account")])
        ]
        context.manager.handleUserChange(using: context.auth)
        await assertEventually { context.cloud.loadAttempts == [firstUserID] }

        context.auth.user = User(id: secondUserID, email: "second@example.com")
        context.manager.handleUserChange(using: context.auth)

        await assertEventually {
            context.cloud.loadAttempts.contains(secondUserID)
                && context.manager.events.map(\.title) == ["Second Account"]
        }
        try? await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(context.manager.events.map(\.title), ["Second Account"])
    }

    func testPendingEventEditRemainsScopedAcrossRoundTripAccountSwitch() async throws {
        let suiteName = "CloudSyncEventsAccountScope.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUserID = "events-first-\(UUID().uuidString)"
        let secondUserID = "events-second-\(UUID().uuidString)"
        let auth = makeAuth(userID: firstUserID)
        let cloud = ScriptedEventsCloud()
        let manager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: cloud,
            cloudLoadRetryDelays: [],
            cloudSaveDebounce: .milliseconds(5),
            cloudSaveRetryDelay: .milliseconds(5)
        )
        let firstOffline = event(title: "First Offline Event")
        let secondRemote = event(title: "Second Remote Event")
        let firstRemote = event(title: "First Remote Event")
        cloud.loadSteps = [
            .failure(TestFailure.offline),
            .failure(TestFailure.offline),
            .success([secondRemote]),
            .success([firstRemote])
        ]

        manager.handleUserChange(using: auth)
        await assertEventually { cloud.loadAttempts == [firstUserID] }
        manager.addEvent(firstOffline)
        await assertEventually {
            cloud.loadAttempts.filter { $0 == firstUserID }.count == 2
        }

        auth.user = User(id: secondUserID, email: "second@example.com")
        manager.handleUserChange(using: auth)
        let loadedSecondEvents = await waitUntil {
            cloud.loadAttempts.contains(secondUserID)
                && manager.events == [secondRemote]
        }
        XCTAssertTrue(
            loadedSecondEvents,
            "attempts=\(cloud.loadAttempts), active=\(manager.events.map(\.title))"
        )

        auth.user = User(id: firstUserID, email: "first@example.com")
        manager.handleUserChange(using: auth)
        let reloadedFirstEvents = await waitUntil {
            cloud.loadAttempts.filter { $0 == firstUserID }.count == 3
                && cloud.saveAttempts.contains { $0.userID == firstUserID }
        }
        XCTAssertTrue(
            reloadedFirstEvents,
            "loads=\(cloud.loadAttempts), saves=\(cloud.saveAttempts.map(\.userID))"
        )

        XCTAssertEqual(
            Set(manager.events.map(\.title)),
            Set(["First Offline Event", "First Remote Event"])
        )
        let firstUserSave = try XCTUnwrap(
            cloud.saveAttempts.last { $0.userID == firstUserID }
        )
        XCTAssertEqual(
            Set(firstUserSave.events.map(\.title)),
            Set(["First Offline Event", "First Remote Event"])
        )
        XCTAssertFalse(firstUserSave.events.contains { $0.title == "Second Remote Event" })
    }

    func testTransientNilAuthKeepsOwnedEventsAndUploadsPreRestoreEdit() async throws {
        let suiteName = "CloudSyncEventsAuthRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "events-auth-restore-\(UUID().uuidString)"
        let auth = makeAuth(userID: userID)
        let existing = event(title: "Owned Before Relaunch")

        let firstCloud = ScriptedEventsCloud()
        firstCloud.loadSteps = [.failure(TestFailure.offline)]
        let firstManager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: firstCloud,
            cloudLoadRetryDelays: []
        )
        firstManager.handleUserChange(using: auth)
        await assertEventually { firstCloud.loadAttempts.count == 1 }
        firstManager.events = [existing]
        firstManager.saveEvents(syncToCloud: false)

        auth.user = nil
        let recoveredCloud = ScriptedEventsCloud()
        let remote = event(title: "Remote")
        recoveredCloud.loadSteps = [.success([remote])]
        let relaunchedManager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: recoveredCloud,
            cloudLoadRetryDelays: [],
            cloudSaveDebounce: .milliseconds(5),
            cloudSaveRetryDelay: .milliseconds(5)
        )
        relaunchedManager.handleUserChange(using: auth)
        let preRestoreEdit = event(title: "Edit During Auth Restore")
        relaunchedManager.addEvent(preRestoreEdit)

        auth.user = User(id: userID, email: "test@example.com")
        relaunchedManager.handleUserChange(using: auth)

        await assertEventually { recoveredCloud.saveAttempts.count == 1 }
        let expectedTitles = Set([
            "Owned Before Relaunch",
            "Edit During Auth Restore",
            "Remote"
        ])
        XCTAssertEqual(Set(relaunchedManager.events.map(\.title)), expectedTitles)
        XCTAssertEqual(
            Set(recoveredCloud.saveAttempts[0].events.map(\.title)),
            expectedTitles
        )
    }

    func testEventRelaunchRestoresPendingScopedSnapshotWhenLegacyActiveCopyIsCorrupt() async throws {
        let suiteName = "CloudSyncEventsCorruptActive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "events-corrupt-active-\(UUID().uuidString)"
        let auth = makeAuth(userID: userID)
        let baseline = event(title: "Cloud Baseline")
        let encodedBaseline = try JSONEncoder().encode([baseline])
        defaults.set(encodedBaseline, forKey: "CustomEvents")
        defaults.set(encodedBaseline, forKey: "LastSyncedCloudEvents.\(userID)")
        defaults.set(true, forKey: "EstablishedCloudEventsBaseline.\(userID)")

        let offlineCloud = ScriptedEventsCloud()
        let offlineManager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: offlineCloud,
            cloudLoadRetryDelays: [],
            cloudSaveDebounce: .milliseconds(5),
            cloudSaveRetryDelay: .milliseconds(5),
            connectivity: TestCloudConnectivity(isConnected: false)
        )
        offlineManager.handleUserChange(using: auth)
        let pending = event(title: "Pending Survives Corruption")
        offlineManager.addEvent(pending)
        XCTAssertNotNil(defaults.data(forKey: "LocalCustomEvents.\(userID)"))

        // Model an interrupted/corrupt write to the legacy global value. With a
        // pending marker, treating this decode failure as [] would delete the
        // baseline event and the unsynced event on the next cloud merge.
        defaults.set(Data([0x00, 0xFF, 0x01, 0xFE]), forKey: "CustomEvents")
        let recoveredCloud = ScriptedEventsCloud()
        recoveredCloud.loadSteps = [.success([baseline])]
        let relaunchedManager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: recoveredCloud,
            cloudLoadRetryDelays: [],
            cloudSaveDebounce: .milliseconds(5),
            cloudSaveRetryDelay: .milliseconds(5)
        )
        relaunchedManager.handleUserChange(using: auth)

        await assertEventually { recoveredCloud.saveAttempts.count == 1 }
        let expectedTitles = Set(["Cloud Baseline", "Pending Survives Corruption"])
        XCTAssertEqual(Set(relaunchedManager.events.map(\.title)), expectedTitles)
        XCTAssertEqual(
            Set(recoveredCloud.saveAttempts[0].events.map(\.title)),
            expectedTitles
        )
    }

    func testCorruptScopedEventSnapshotFailsClosedWithoutCloudWrite() async throws {
        let suiteName = "CloudSyncEventsCorruptLocal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "events-corrupt-local-\(UUID().uuidString)"
        let otherUserID = "events-other-\(UUID().uuidString)"
        let otherEvent = event(title: "Other Account")
        let corrupt = Data([0x00, 0xFF, 0x01, 0xFE])
        defaults.set("user:\(otherUserID)", forKey: "LocalCustomEventsOwner")
        defaults.set(try JSONEncoder().encode([otherEvent]), forKey: "CustomEvents")
        defaults.set(corrupt, forKey: "LocalCustomEvents.\(userID)")

        let cloud = ScriptedEventsCloud()
        cloud.loadSteps = [.success([event(title: "Cloud Must Stay Untouched")])]
        let manager = CustomEventsManager(userDefaults: defaults, cloudSync: cloud)
        let auth = makeAuth(userID: userID)

        manager.handleUserChange(using: auth)
        manager.retryCloudSync(force: true)
        manager.addEvent(event(title: "Blocked Target Edit"))
        manager.retryCloudSync(force: true)
        await manager.flushCloudSync()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(cloud.loadAttempts.isEmpty)
        XCTAssertTrue(cloud.saveAttempts.isEmpty)
        XCTAssertTrue(manager.events.isEmpty)
        XCTAssertEqual(
            try JSONDecoder().decode(
                [CustomEvent].self,
                from: XCTUnwrap(defaults.data(forKey: "CustomEvents"))
            ),
            [otherEvent]
        )
        XCTAssertEqual(
            defaults.string(forKey: "LocalCustomEventsOwner"),
            "user:\(otherUserID)"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                [CustomEvent].self,
                from: XCTUnwrap(
                    defaults.data(forKey: "LocalCustomEvents.\(otherUserID)")
                )
            ),
            [otherEvent]
        )
        XCTAssertEqual(
            defaults.data(forKey: "LocalCustomEvents.\(userID)"),
            corrupt
        )
        guard case .failed = manager.cloudSyncPhase else {
            return XCTFail("Corrupt local events must fence cloud sync")
        }
    }

    func testSameOwnerCorruptEventSnapshotFencesPreactivationEditAndRetry() async throws {
        let suiteName = "CloudSyncEventsSameOwnerCorrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "events-same-owner-corrupt-\(UUID().uuidString)"
        let corrupt = Data([0x00, 0xFF, 0x01, 0xFE])
        let baseline = event(title: "Remote Baseline")
        let encodedBaseline = try JSONEncoder().encode([baseline])
        defaults.set("user:\(userID)", forKey: "LocalCustomEventsOwner")
        defaults.set(corrupt, forKey: "CustomEvents")
        defaults.set(corrupt, forKey: "LocalCustomEvents.\(userID)")
        defaults.set(true, forKey: "PendingCloudEvents.\(userID)")
        defaults.set(encodedBaseline, forKey: "LastSyncedCloudEvents.\(userID)")
        defaults.set(true, forKey: "EstablishedCloudEventsBaseline.\(userID)")

        let cloud = ScriptedEventsCloud()
        cloud.loadSteps = [.success([baseline])]
        let manager = CustomEventsManager(userDefaults: defaults, cloudSync: cloud)
        let auth = makeAuth(userID: userID)

        manager.setAuthManager(auth)
        manager.addEvent(event(title: "Preactivation Bypass"))
        manager.handleUserChange(using: auth)
        manager.retryCloudSync(force: true)
        manager.addEvent(event(title: "Postactivation Bypass"))
        await manager.flushCloudSync()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(manager.events.isEmpty)
        XCTAssertTrue(cloud.loadAttempts.isEmpty)
        XCTAssertTrue(cloud.saveAttempts.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "CustomEvents"), corrupt)
        XCTAssertEqual(
            defaults.data(forKey: "LocalCustomEvents.\(userID)"),
            corrupt
        )
        XCTAssertTrue(defaults.bool(forKey: "PendingCloudEvents.\(userID)"))
        XCTAssertEqual(
            defaults.data(forKey: "LastSyncedCloudEvents.\(userID)"),
            encodedBaseline
        )
        guard case .failed = manager.cloudSyncPhase else {
            return XCTFail("Same-owner corrupt events must keep their durable fence")
        }
    }

    func testPendingEventEditSurvivesManagerRecreation() async throws {
        let suiteName = "CloudSyncResilienceEvents.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "events-persist-\(UUID().uuidString)"
        let auth = makeAuth(userID: userID)
        let local = event(title: "Persisted Offline")

        let offlineCloud = ScriptedEventsCloud()
        offlineCloud.loadSteps = [.failure(TestFailure.offline)]
        let firstManager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: offlineCloud,
            cloudLoadRetryDelays: [],
            cloudSaveDebounce: .milliseconds(5),
            cloudSaveRetryDelay: .milliseconds(5)
        )
        firstManager.handleUserChange(using: auth)
        firstManager.addEvent(local)
        await assertEventually { offlineCloud.loadAttempts.count == 1 }
        XCTAssertTrue(offlineCloud.saveAttempts.isEmpty)

        auth.user = nil
        firstManager.handleUserChange(using: auth)

        let recoveredCloud = ScriptedEventsCloud()
        recoveredCloud.loadSteps = [.success([event(title: "Remote Event")])]
        let secondManager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: recoveredCloud,
            cloudLoadRetryDelays: [.milliseconds(5)],
            cloudSaveDebounce: .milliseconds(5),
            cloudSaveRetryDelay: .milliseconds(5)
        )
        auth.user = User(id: userID, email: "test@example.com")
        secondManager.handleUserChange(using: auth)

        await assertEventually { recoveredCloud.saveAttempts.count == 1 }
        XCTAssertEqual(
            Set(secondManager.events.map(\.title)),
            Set(["Persisted Offline", "Remote Event"])
        )
        XCTAssertEqual(
            Set(recoveredCloud.saveAttempts[0].events.map(\.title)),
            Set(["Persisted Offline", "Remote Event"])
        )
    }

    func testTwoDevicesAddingDifferentEventsMergesWithoutDataLoss() async throws {
        let context = try makeEventsContext(saveDebounce: .milliseconds(30))
        let original = event(title: "Original")
        let localAddition = event(title: "Local Addition")
        let remoteAddition = event(title: "Remote Addition")
        context.cloud.loadSteps = [.success([original])]
        context.manager.handleUserChange(using: context.auth)
        await assertEventually { context.manager.events == [original] }

        context.manager.addEvent(localAddition)
        context.cloud.emit([original, remoteAddition])

        await assertEventually { context.cloud.saveAttempts.count == 1 }
        XCTAssertEqual(
            Set(context.manager.events.map(\.title)),
            Set(["Original", "Local Addition", "Remote Addition"])
        )
        XCTAssertEqual(
            Set(context.cloud.saveAttempts[0].events.map(\.title)),
            Set(["Original", "Local Addition", "Remote Addition"])
        )
    }

    func testRemoteFinalEventDeletionPropagatesToOtherDevice() async throws {
        let context = try makeEventsContext()
        let original = event(title: "Delete Remotely")
        context.cloud.loadSteps = [.success([original])]
        context.manager.handleUserChange(using: context.auth)
        await assertEventually { context.manager.events == [original] }

        context.cloud.emit([])

        await assertEventually { context.manager.events.isEmpty }
        XCTAssertTrue(context.cloud.saveAttempts.isEmpty)
    }

    func testDeleteRacingRemoteEditPreservesEditedEvent() {
        let original = event(title: "Original")
        var edited = original
        edited.title = "Edited Elsewhere"

        let merged = CustomEventsManager.mergeEvents(
            base: [original],
            local: [],
            remote: [edited]
        )

        XCTAssertEqual(merged, [edited])
    }

    func testFiveHundredRapidScheduleEditsCoalesceIntoOneLatestUpload() async throws {
        let context = try makeScheduleContext(saveDebounce: .milliseconds(80))
        let remote = schedule(named: "Remote", secondLunch: [false, false])
        context.cloud.loadSteps = [.success(scheduleState(remote))]
        context.store.data = remote
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        for index in 0..<500 {
            var edited = context.store.data ?? remote
            edited.classes[0].name = "Edit \(index)"
            context.store.updateSchedule(edited, authManager: context.auth)
        }

        await assertEventually(timeout: .seconds(2)) {
            context.cloud.saveAttempts.count == 1
        }
        XCTAssertEqual(context.cloud.saveAttempts[0].classes[0].name, "Edit 499")
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(context.cloud.saveAttempts.count, 1)
    }

    func testThreeHundredRapidEventAddsCoalesceIntoOneCompleteUpload() async throws {
        let context = try makeEventsContext(saveDebounce: .milliseconds(80))
        context.cloud.loadSteps = [.success([])]
        context.manager.handleUserChange(using: context.auth)
        await assertEventually { context.cloud.loadAttempts.count == 1 }

        for index in 0..<300 {
            context.manager.addEvent(event(title: "Event \(index)"))
        }

        await assertEventually(timeout: .seconds(3)) {
            context.cloud.saveAttempts.count == 1
        }
        XCTAssertEqual(context.cloud.saveAttempts[0].events.count, 300)
        XCTAssertEqual(context.cloud.saveAttempts[0].events.last?.title, "Event 299")
        XCTAssertEqual(Set(context.cloud.saveAttempts[0].events.map(\.id)).count, 300)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(context.cloud.saveAttempts.count, 1)
    }

    func testCancellingVerySlowScheduleLoadDoesNotBlockAccountSwitch() async throws {
        let context = try makeScheduleContext()
        let secondUserID = "fast-schedule-\(UUID().uuidString)"
        context.cloud.loadSteps = [
            .success(
                scheduleState(schedule(named: "Stale", secondLunch: [true, true])),
                delay: .seconds(30)
            ),
            .success(scheduleState(schedule(named: "Current", secondLunch: [false, true])))
        ]
        context.store.data = schedule(named: "Local", secondLunch: [false, false])
        context.store.handleUserChange(context.userID, authManager: context.auth)
        await assertEventually { context.cloud.loadAttempts == [context.userID] }

        let clock = ContinuousClock()
        let switchedAt = clock.now
        context.auth.user = User(id: secondUserID, email: "fast@example.com")
        context.store.handleUserChange(secondUserID, authManager: context.auth)

        await assertEventually(timeout: .seconds(1)) {
            context.cloud.loadAttempts.contains(secondUserID)
                && context.store.data?.classes[0].name == "Current"
        }
        XCTAssertLessThan(switchedAt.duration(to: clock.now), .seconds(1))
        XCTAssertEqual(context.store.data?.isSecondLunch, [false, true])
    }

    func testCancellingVerySlowEventLoadDoesNotBlockAccountSwitch() async throws {
        let context = try makeEventsContext()
        let secondUserID = "fast-events-\(UUID().uuidString)"
        context.cloud.loadSteps = [
            .success([event(title: "Stale")], delay: .seconds(30)),
            .success([event(title: "Current")])
        ]
        context.manager.handleUserChange(using: context.auth)
        await assertEventually { context.cloud.loadAttempts == [context.userID] }

        let clock = ContinuousClock()
        let switchedAt = clock.now
        context.auth.user = User(id: secondUserID, email: "fast@example.com")
        context.manager.handleUserChange(using: context.auth)

        await assertEventually(timeout: .seconds(1)) {
            context.cloud.loadAttempts.contains(secondUserID)
                && context.manager.events.map(\.title) == ["Current"]
        }
        XCTAssertLessThan(switchedAt.duration(to: clock.now), .seconds(1))
    }

    func testThousandUsageSnapshotsReuseOneIDUntilSessionEnds() throws {
        let store = UsageStatsStore()
        let startedAt = Date(timeIntervalSince1970: 1_000_000)
        store.setUserScope("stress-user")
        store.beginSession(at: startedAt)
        store.setCurrentPage(.home, at: startedAt)

        var snapshotIDs = Set<String>()
        for offset in 1...1_000 {
            let snapshot = try XCTUnwrap(
                store.snapshotSession(at: startedAt.addingTimeInterval(Double(offset)))
            )
            snapshotIDs.insert(snapshot.id)
        }
        let ended = try XCTUnwrap(
            store.endSession(at: startedAt.addingTimeInterval(1_001))
        )

        XCTAssertEqual(snapshotIDs, [ended.id])

        store.beginSession(at: startedAt.addingTimeInterval(2_000))
        let next = try XCTUnwrap(
            store.endSession(at: startedAt.addingTimeInterval(2_001))
        )
        XCTAssertNotEqual(next.id, ended.id)
    }

    func testLargeThreeWayEventMergeIsUniqueAndDoesNotDropIndependentChanges() {
        let base = (0..<600).map { indexedEvent($0, title: "Base \($0)") }
        var local: [CustomEvent] = []
        var remote: [CustomEvent] = []

        for (index, event) in base.enumerated() {
            var localEdit = event
            localEdit.title = "Local \(index)"
            var remoteEdit = event
            remoteEdit.title = "Remote \(index)"

            switch index % 6 {
            case 0:
                local.append(event)
                remote.append(remoteEdit)
            case 1:
                local.append(localEdit)
                remote.append(event)
            case 2:
                remote.append(remoteEdit)
            case 3:
                local.append(localEdit)
            case 4:
                break
            default:
                local.append(event)
                remote.append(event)
            }
        }

        let localAdds = (600..<800).map { indexedEvent($0, title: "Local add \($0)") }
        let remoteAdds = (800..<1_000).map { indexedEvent($0, title: "Remote add \($0)") }
        local.append(contentsOf: localAdds)
        remote.append(contentsOf: remoteAdds)

        // Duplicate input records emulate legacy arrays and repeated listener
        // delivery. The merge must still emit one record per logical ID.
        local.append(contentsOf: localAdds.prefix(50))
        remote.append(contentsOf: remoteAdds.prefix(50))

        let merged = CustomEventsManager.mergeEvents(
            base: base,
            local: local,
            remote: remote
        )

        XCTAssertEqual(merged.count, 900)
        XCTAssertEqual(Set(merged.map(\.id)).count, merged.count)
        let mergedByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        for index in 0..<600 {
            let title = mergedByID[indexedUUID(index)]?.title
            switch index % 6 {
            case 0, 2:
                XCTAssertEqual(title, "Remote \(index)")
            case 1, 3:
                XCTAssertEqual(title, "Local \(index)")
            case 4:
                XCTAssertNil(title)
            default:
                XCTAssertEqual(title, "Base \(index)")
            }
        }
        XCTAssertTrue(localAdds.allSatisfy { mergedByID[$0.id] == $0 })
        XCTAssertTrue(remoteAdds.allSatisfy { mergedByID[$0.id] == $0 })
    }

    func testRepeatedForegroundRetriesDoNotAmplifyCloudReadsOrWrites() async throws {
        let scheduleContext = try makeScheduleContext()
        let remote = schedule(named: "Remote", secondLunch: [false, false])
        scheduleContext.cloud.loadSteps = [.success(scheduleState(remote))]
        scheduleContext.store.data = remote
        scheduleContext.store.handleUserChange(
            scheduleContext.userID,
            authManager: scheduleContext.auth
        )
        await assertEventually { scheduleContext.cloud.loadAttempts.count == 1 }

        let eventsContext = try makeEventsContext()
        eventsContext.cloud.loadSteps = [.success([])]
        eventsContext.manager.handleUserChange(using: eventsContext.auth)
        await assertEventually { eventsContext.cloud.loadAttempts.count == 1 }

        for _ in 0..<1_000 {
            scheduleContext.store.retryCloudSync(authManager: scheduleContext.auth)
            eventsContext.manager.retryCloudSync()
        }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(scheduleContext.cloud.loadAttempts.count, 1)
        XCTAssertTrue(scheduleContext.cloud.saveAttempts.isEmpty)
        XCTAssertEqual(eventsContext.cloud.loadAttempts.count, 1)
        XCTAssertTrue(eventsContext.cloud.saveAttempts.isEmpty)
    }

    // MARK: - Helpers

    private struct ScheduleContext {
        let store: GlobalDataStore
        let cloud: ScriptedScheduleCloud
        let auth: AuthenticationManager
        let userID: String
    }

    private struct EventsContext {
        let manager: CustomEventsManager
        let cloud: ScriptedEventsCloud
        let auth: AuthenticationManager
        let userID: String
        let defaults: UserDefaults
    }

    private func makeScheduleContext(
        loadRetryDelays: [Duration] = [.milliseconds(5)],
        saveDebounce: Duration = .milliseconds(5),
        saveRetryDelay: Duration = .milliseconds(5),
        connectivity: any CloudConnectivityChecking = TestCloudConnectivity(isConnected: true)
    ) throws -> ScheduleContext {
        let suiteName = "CloudSyncSchedule.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "schedule-\(UUID().uuidString)"
        let cloud = ScriptedScheduleCloud()
        return ScheduleContext(
            store: makeScheduleStore(
                defaults: defaults,
                cloud: cloud,
                loadRetryDelays: loadRetryDelays,
                saveDebounce: saveDebounce,
                saveRetryDelay: saveRetryDelay,
                connectivity: connectivity
            ),
            cloud: cloud,
            auth: makeAuth(userID: userID),
            userID: userID
        )
    }

    private func makeScheduleStore(
        defaults: UserDefaults,
        cloud: ScriptedScheduleCloud,
        loadRetryDelays: [Duration] = [.milliseconds(5)],
        saveDebounce: Duration = .milliseconds(5),
        saveRetryDelay: Duration = .milliseconds(5),
        connectivity: any CloudConnectivityChecking = TestCloudConnectivity(isConnected: true)
    ) -> GlobalDataStore {
        GlobalDataStore(
            persistence: CloudService(userDefaults: defaults),
            cloudSync: cloud,
            userDefaults: defaults,
            cloudLoadRetryDelays: loadRetryDelays,
            cloudSaveDebounce: saveDebounce,
            cloudSaveRetryDelay: saveRetryDelay,
            connectivity: connectivity
        )
    }

    private func makeEventsContext(
        loadRetryDelays: [Duration] = [.milliseconds(5)],
        saveDebounce: Duration = .milliseconds(5),
        saveRetryDelay: Duration = .milliseconds(5)
    ) throws -> EventsContext {
        let suiteName = "CloudSyncEvents.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "events-\(UUID().uuidString)"
        let cloud = ScriptedEventsCloud()
        return EventsContext(
            manager: CustomEventsManager(
                userDefaults: defaults,
                cloudSync: cloud,
                cloudLoadRetryDelays: loadRetryDelays,
                cloudSaveDebounce: saveDebounce,
                cloudSaveRetryDelay: saveRetryDelay
            ),
            cloud: cloud,
            auth: makeAuth(userID: userID),
            userID: userID,
            defaults: defaults
        )
    }

    private func makeAuth(userID: String) -> AuthenticationManager {
        let auth = AuthenticationManager(startAuthStateListener: false)
        auth.user = User(id: userID, email: "test@example.com")
        return auth
    }

    private func schedule(named name: String, secondLunch: [Bool]) -> ScheduleData {
        var classes = ScheduleData.defaultClasses
        classes[0].name = name
        classes[0].teacher = "Teacher"
        classes[0].room = "101"
        return ScheduleData(
            classes: classes,
            days: [Day(name: "Gold")],
            isSecondLunch: secondLunch
        ).normalized()
    }

    private func scheduleState(
        _ data: ScheduleData,
        theme: ThemeColors = .defaultTheme
    ) -> PersistedScheduleState {
        PersistedScheduleState(
            classes: data.classes,
            days: data.days,
            isSecondLunch: data.isSecondLunch,
            theme: PersistedThemeState(theme: theme)
        )
    }

    private func apply(_ theme: ThemeColors, to store: GlobalDataStore) {
        store.primaryColor = Color(hex: theme.primary)
        store.secondaryColor = Color(hex: theme.secondary)
        store.tertiaryColor = Color(hex: theme.tertiary)
        store.primaryFontChoice = theme.primaryFontChoice
        store.secondaryFontChoice = theme.secondaryFontChoice
    }

    private func event(title: String) -> CustomEvent {
        CustomEvent(
            title: title,
            startTime: Time("9:00"),
            endTime: Time("10:00"),
            repeatPattern: .daily
        )
    }

    private func indexedEvent(_ index: Int, title: String) -> CustomEvent {
        CustomEvent(
            id: indexedUUID(index),
            title: title,
            startTime: Time("9:00"),
            endTime: Time("10:00"),
            repeatPattern: .daily
        )
    }

    private func indexedUUID(_ index: Int) -> UUID {
        let suffix = String(format: "%012x", index)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    private func assertEventually(
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let succeeded = await waitUntil(timeout: timeout, condition: condition)
        XCTAssertTrue(succeeded, file: file, line: line)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }
}

private final class TestCloudConnectivity: CloudConnectivityChecking {
    var isConnected: Bool

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }
}

@MainActor
private final class ScriptedScheduleCloud: ScheduleCloudSyncing {
    struct LoadStep {
        let result: Result<PersistedScheduleState, Error>
        let delay: Duration

        static func success(
            _ state: PersistedScheduleState,
            delay: Duration = .zero
        ) -> LoadStep {
            LoadStep(result: .success(state), delay: delay)
        }

        static func failure(
            _ error: Error,
            delay: Duration = .zero
        ) -> LoadStep {
            LoadStep(result: .failure(error), delay: delay)
        }
    }

    struct SaveAttempt {
        let classes: [ClassItem]
        let theme: ThemeColors
        let isSecondLunch: [Bool]
        let userID: String
    }

    var loadSteps: [LoadStep] = []
    var saveResults: [Result<Void, Error>] = []
    private(set) var loadAttempts: [String] = []
    private(set) var saveAttempts: [SaveAttempt] = []

    func loadCloudScheduleState(
        for userId: String,
        days: [Day]
    ) async throws -> PersistedScheduleState {
        loadAttempts.append(userId)
        guard !loadSteps.isEmpty else {
            throw URLError(.notConnectedToInternet)
        }
        let step = loadSteps.removeFirst()
        if step.delay != .zero {
            try? await Task.sleep(for: step.delay)
        }
        return try step.result.get()
    }

    func saveScheduleToCloud(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        userId: String
    ) async throws {
        saveAttempts.append(SaveAttempt(
            classes: classes,
            theme: theme,
            isSecondLunch: isSecondLunch,
            userID: userId
        ))
        guard !saveResults.isEmpty else { return }
        try saveResults.removeFirst().get()
    }
}

@MainActor
private final class ScriptedEventsCloud: EventsCloudSyncing {
    struct LoadStep {
        let result: Result<[CustomEvent], Error>
        let delay: Duration
        let isAuthoritative: Bool

        static func success(
            _ events: [CustomEvent],
            delay: Duration = .zero,
            isAuthoritative: Bool = true
        ) -> LoadStep {
            LoadStep(
                result: .success(events),
                delay: delay,
                isAuthoritative: isAuthoritative
            )
        }

        static func failure(
            _ error: Error,
            delay: Duration = .zero
        ) -> LoadStep {
            LoadStep(result: .failure(error), delay: delay, isAuthoritative: true)
        }
    }

    struct SaveAttempt {
        let events: [CustomEvent]
        let userID: String
    }

    var loadSteps: [LoadStep] = []
    var saveResults: [Result<Void, Error>] = []
    private(set) var loadAttempts: [String] = []
    private(set) var saveAttempts: [SaveAttempt] = []
    private var observer: (@MainActor (Result<[CustomEvent], Error>) -> Void)?

    func loadEvents(for userId: String) async throws -> [CustomEvent] {
        try await loadEventState(for: userId).events
    }

    func loadEventState(for userId: String) async throws -> PersistedEventsState {
        loadAttempts.append(userId)
        guard !loadSteps.isEmpty else {
            throw URLError(.notConnectedToInternet)
        }
        let step = loadSteps.removeFirst()
        if step.delay != .zero {
            try? await Task.sleep(for: step.delay)
        }
        return PersistedEventsState(
            events: try step.result.get(),
            isAuthoritative: step.isAuthoritative
        )
    }

    func saveEvents(_ events: [CustomEvent], for userId: String) async throws {
        saveAttempts.append(SaveAttempt(events: events, userID: userId))
        guard !saveResults.isEmpty else { return }
        try saveResults.removeFirst().get()
    }

    func observeEvents(
        for userId: String,
        onChange: @escaping @MainActor (Result<[CustomEvent], Error>) -> Void
    ) -> CloudSyncObservation? {
        observer = onChange
        return CloudSyncObservation { [weak self] in
            self?.observer = nil
        }
    }

    func emit(_ events: [CustomEvent]) {
        observer?(.success(events))
    }
}
