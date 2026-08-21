import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import XCTest
@testable import Schedule

@MainActor
final class FirebaseEmulatorIntegrationTests: XCTestCase {
    private static var configured = false
    private var uid = ""

    override func setUp() async throws {
        try await super.setUp()
        #if FIREBASE_EMULATOR_TESTS
        let emulatorTestsEnabled = true
        #else
        let emulatorTestsEnabled = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_TESTS"] == "1"
        #endif
        guard emulatorTestsEnabled else {
            throw XCTSkip("Run with Firebase emulators and FIREBASE_EMULATOR_TESTS=1.")
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        if !Self.configured {
            Auth.auth().useEmulator(withHost: "localhost", port: 9099)
            Firestore.firestore().useEmulator(withHost: "localhost", port: 8080)
            let emulatorSettings = Firestore.firestore().settings
            emulatorSettings.isSSLEnabled = false
            emulatorSettings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = emulatorSettings
            Self.configured = true
        }

        try? Auth.auth().signOut()
        uid = try await Auth.auth().signInAnonymously().user.uid
    }

    override func tearDown() async throws {
        // Every test signs in as a fresh anonymous UID. Do not invoke the
        // client deletion workflow for fixture cleanup: a committed deletion
        // request is intentionally immutable and makes the user tree
        // unreadable. The emulator process owns and discards these documents.
        try? await Auth.auth().currentUser?.delete()
        try await super.tearDown()
    }

    func testDeployedRulesRejectCrossUserAccess() async throws {
        let otherUser = "other-\(UUID().uuidString)"
        do {
            try await Firestore.firestore().collection("users").document(otherUser)
                .setData(["uid": otherUser])
            XCTFail("Owner-only rules accepted a cross-user write.")
        } catch {
            XCTAssertEqual((error as NSError).domain, FirestoreErrorDomain)
        }
    }

    func testMissingRootWithoutDeletionRequestCanReadRecoveryDocumentsButCannotWrite() async throws {
        try await seedCanonicalDocument()
        let legacyState = userDocument.collection("sync").document("state")
        let legacySession = legacyState.collection("sessions").document("orphan-session")
        try await legacyState.setData(["uid": uid, "fixture": "orphan-recovery"])
        try await legacySession.setData([
            "id": "orphan-session",
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))
        ])

        // Firestore does not remove subcollections with their parent. A new
        // install must be able to discover these recovery documents when the
        // root is accidentally absent, unless a durable deletion request says
        // the absence is intentional.
        try await emulatorAdminDeleteDocument(userDocument)
        let requestAfterRootDeletion = try await deletionRequestDocument.getDocument()
        let rootAfterDeletion = try await userDocument.getDocument()
        let stateAfterRootDeletion = try await legacyState.getDocument()
        let sessionAfterRootDeletion = try await legacySession.getDocument()
        XCTAssertFalse(requestAfterRootDeletion.exists)
        XCTAssertFalse(rootAfterDeletion.exists)
        XCTAssertTrue(stateAfterRootDeletion.exists)
        XCTAssertTrue(sessionAfterRootDeletion.exists)

        await assertPermissionDenied("sync update without user root") {
            try await legacyState.setData(["postRootDelete": true], merge: true)
        }
        await assertPermissionDenied("session update without user root") {
            try await legacySession.setData(["postRootDelete": true], merge: true)
        }
    }

    func testLegacyMigrationPreservesAllDomainsAndRecoveryDocuments() async throws {
        let root = userDocument
        let legacyState = root.collection("sync").document("state")
        let classID = UUID()
        let eventID = UUID()

        try await root.setData([
            "uid": uid,
            "classes": [[
                "id": classID.uuidString,
                "name": "Legacy Math",
                "teacher": "Teacher",
                "room": "101"
            ]],
            "theme": [
                "primary": "#112233FF",
                "secondary": "#445566FF",
                "tertiary": "#FFFFFFFF"
            ],
            "isSecondLunch": [true, false]
        ])
        try await legacyState.setData([
            "customEvents": [[
                "id": eventID.uuidString,
                "title": "Legacy Event",
                "startTime": ["h": 8, "m": 0, "s": 0],
                "endTime": ["h": 9, "m": 0, "s": 0],
                "location": "Library",
                "note": "Preserve me",
                "color": "#FF0000",
                "repeatPattern": RepeatPattern.none.rawValue,
                "kind": CustomItemKind.event.rawValue,
                "applicableDays": ["G1"]
            ]]
        ])

        let schedule = try await DataManager().loadFromCloud(for: uid)
        let events = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        let migratedSnapshot = try await root.getDocument()
        let migrated = migratedSnapshot.data()

        XCTAssertEqual(schedule.0.first?.id, classID)
        XCTAssertEqual(schedule.0.first?.name, "Legacy Math")
        XCTAssertEqual(schedule.2, [true, false])
        XCTAssertEqual(events.first?.id, eventID)
        XCTAssertTrue(DataManager.isCanonicalUserDocument(migrated ?? [:]))
        let legacyStateSnapshot = try await legacyState.getDocument()
        XCTAssertTrue(legacyStateSnapshot.exists)
    }

    func testPre118EmbeddedRootSessionsGetStableIDsDeduplicateAndRemainIdempotent() async throws {
        let root = userDocument
        let firstSession: [String: Any] = [
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000)),
            "endedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_120)),
            "appVersion": "1.17.3"
        ]
        let secondSession: [String: Any] = [
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_300)),
            "endedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_480)),
            "appVersion": "1.16.4"
        ]

        try await root.setData([
            "uid": uid,
            "classes": [],
            "theme": [
                "primary": "#112233FF",
                "secondary": "#445566FF",
                "tertiary": "#FFFFFFFF"
            ],
            "isSecondLunch": [false, false],
            "usageStats": ["sessions": [firstSession]]
        ])

        // This is the exact 1.16-1.17 writer shape. Because setData treats the
        // dictionary key literally, it can coexist with the nested map above.
        try await root.setData([
            "usageStats.sessions": FieldValue.arrayUnion([firstSession, secondSession])
        ], merge: true)

        let seededRoot = try await documentData(root)
        let nestedUsageStats = try XCTUnwrap(seededRoot["usageStats"] as? [String: Any])
        XCTAssertEqual((nestedUsageStats["sessions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((seededRoot["usageStats.sessions"] as? [[String: Any]])?.count, 2)

        _ = try await DataManager().loadFromCloud(for: uid)
        var canonical = try await root.collection("sessions").getDocuments().documents
        XCTAssertEqual(canonical.count, 2)
        XCTAssertTrue(canonical.allSatisfy {
            !$0.documentID.isEmpty && $0.data()["id"] as? String == $0.documentID
        })
        let firstMigrationIDs = Set(canonical.map(\.documentID))

        // Delete the derived records and force the backfill to prove IDs are a
        // deterministic function of legacy content, not random UUIDs.
        for document in canonical {
            try await emulatorAdminDeleteDocument(document.reference)
        }
        try await root.updateData([
            "usageSessionMigrationVersion": FieldValue.delete()
        ])

        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        canonical = try await root.collection("sessions").getDocuments().documents
        XCTAssertEqual(Set(canonical.map(\.documentID)), firstMigrationIDs)
        XCTAssertEqual(canonical.count, 2)

        // A second forced pass must not append duplicates or alter identities.
        try await root.updateData(["usageSessionMigrationVersion": FieldValue.delete()])
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        canonical = try await root.collection("sessions").getDocuments().documents
        XCTAssertEqual(Set(canonical.map(\.documentID)), firstMigrationIDs)
        XCTAssertEqual(canonical.count, 2)

        let migratedRoot = try await documentData(root)
        XCTAssertNotNil(migratedRoot["usageStats"])
        XCTAssertNotNil(migratedRoot["usageStats.sessions"])
    }

    func testPre118ClearShapeDoesNotResurrectStaleLiteralSessions() async throws {
        let oldSession: [String: Any] = [
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_600_000_000)),
            "endedAt": Timestamp(date: Date(timeIntervalSince1970: 1_600_000_120)),
            "appVersion": "1.17.3"
        ]
        try await userDocument.setData([
            "uid": uid,
            "classes": [],
            "theme": plaintextTheme,
            "isSecondLunch": [false, false],
            "usageStats.sessions": [oldSession]
        ])
        // This is the exact historical clear shape: the nested empty array did
        // not delete the separate literal dotted field written by arrayUnion.
        try await userDocument.setData([
            "usageStats": ["sessions": []],
            "usageStatsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_600_000_300)
            )
        ], merge: true)

        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)

        let canonical = try await userDocument.collection("sessions").getDocuments()
        XCTAssertTrue(canonical.documents.isEmpty)
        let retained = try await documentData(userDocument)
        XCTAssertNotNil(retained["usageSessionsClearedAt"] as? Timestamp)
        XCTAssertNil(retained["usageStats.sessions"])
        let retainedUsage = try XCTUnwrap(retained["usageStats"] as? [String: Any])
        XCTAssertTrue((retainedUsage["sessions"] as? [[String: Any]] ?? []).isEmpty)
    }

    func testPre118ClearAfterMigrationDeletesAlreadyCanonicalizedSessions() async throws {
        let oldSession: [String: Any] = [
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_600_000_000)),
            "endedAt": Timestamp(date: Date(timeIntervalSince1970: 1_600_000_120)),
            "appVersion": "1.17.3"
        ]
        try await userDocument.setData([
            "uid": uid,
            "classes": [],
            "theme": plaintextTheme,
            "isSecondLunch": [false, false],
            "usageStats.sessions": [oldSession],
            "usageStatsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_600_000_150)
            )
        ])
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        var canonical = try await userDocument.collection("sessions").getDocuments()
        XCTAssertEqual(canonical.documents.count, 1)

        // The old Clear implementation creates this nested empty array but
        // leaves the dotted writer field above untouched.
        try await userDocument.setData([
            "usageStats": ["sessions": []],
            "usageStatsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_600_000_300)
            )
        ], merge: true)
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)

        canonical = try await userDocument.collection("sessions").getDocuments()
        XCTAssertTrue(canonical.documents.isEmpty)
        let cleared = try await documentData(userDocument)
        XCTAssertNotNil(cleared["usageSessionsClearedAt"] as? Timestamp)
    }

    func testLegacyRootFieldsRemainAfterMigration() async throws {
        let classID = UUID(uuidString: "B780E083-B02A-43D2-A402-2E66ED0E819C")!
        let eventID = UUID(uuidString: "F267C60E-1A5B-42D4-85B8-BE0F53DBBBA0")!
        let legacyClass: [String: Any] = [
            "id": classID.uuidString,
            "name": "Legacy Biology",
            "teacher": "Darwin",
            "room": "204"
        ]
        let legacyEvent = plaintextEvent(
            id: eventID,
            title: "Legacy Assembly",
            repeatPattern: RepeatPattern.none.rawValue
        )

        try await userDocument.setData([
            "uid": uid,
            "classes": [legacyClass],
            "theme": plaintextTheme,
            "isSecondLunch": [true, false],
            "customEvents": [legacyEvent],
            "legacySentinel": ["owner": "released-client", "value": 17]
        ])

        _ = try await DataManager().loadFromCloud(for: uid)
        _ = try await CloudEventsDataManager.shared.loadEvents(for: uid)

        let migrated = try await documentData(userDocument)
        let recovery = try XCTUnwrap(migrated["migrationRecoveryLegacy"] as? [String: Any])
        let classes = try XCTUnwrap(recovery["classes"] as? [[String: Any]])
        let events = try XCTUnwrap(recovery["customEvents"] as? [[String: Any]])
        let theme = try XCTUnwrap(recovery["theme"] as? [String: Any])
        let sentinel = try XCTUnwrap(migrated["legacySentinel"] as? [String: Any])
        XCTAssertEqual(classes.first?["id"] as? String, classID.uuidString)
        XCTAssertEqual(events.first?["id"] as? String, eventID.uuidString)
        XCTAssertEqual(theme["primary"] as? String, "#112233FF")
        XCTAssertEqual(recovery["isSecondLunch"] as? [Bool], [true, false])
        XCTAssertEqual(sentinel["owner"] as? String, "released-client")
        XCTAssertEqual((sentinel["value"] as? NSNumber)?.intValue, 17)
        XCTAssertEqual(migrated["encrypted"] as? Bool, true)
        XCTAssertEqual(migrated["eventsEncrypted"] as? Bool, true)
        let releasedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let releasedTheme = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["theme"] as? String),
            as: ThemeColors.self,
            userId: uid
        )
        let releasedLunches = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["isSecondLunch"] as? String),
            as: [Bool].self,
            userId: uid
        )
        let releasedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["customEvents"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(releasedClasses.first?.id, classID)
        XCTAssertEqual(releasedTheme.primary, "#112233FF")
        XCTAssertEqual(releasedLunches, [true, false])
        XCTAssertEqual(releasedEvents.first?.id, eventID)
        XCTAssertEqual(canonicalSchemaVersion(in: migrated), 5)
    }

    func testVersion4EncryptedMapMigratesToVersion5CloudData() async throws {
        let classID = UUID(uuidString: "204CD7DA-4E1B-430D-A3E2-7C8DE45064B3")!
        let eventID = UUID(uuidString: "4C2201EA-0E94-42DD-A2D5-557E66E9C931")!
        let classes = [ClassItem(
            id: classID,
            name: "Version Four",
            teacher: "Migration",
            room: "V4"
        )]
        let events = [CustomEvent(
            id: eventID,
            title: "V4 Event",
            startTime: Time(h: 9, m: 0, s: 0),
            endTime: Time(h: 10, m: 0, s: 0),
            applicableDays: ["G1"]
        )]
        let version4 = try encryptedMap(
            schemaVersion: 4,
            classes: classes,
            events: events,
            updatedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
        let version4Schedule = try XCTUnwrap(version4["schedule"] as? String)

        try await userDocument.setData([
            "uid": uid,
            "encrypted": version4,
            "legacySentinel": "retain-v4-source"
        ])

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0.first?.id, classID)
        XCTAssertEqual(loadedEvents.first?.id, eventID)

        let migrated = try await documentData(userDocument)
        let retainedVersion4 = try XCTUnwrap(migrated["migrationRecoveryV4"] as? [String: Any])
        XCTAssertEqual(canonicalSchemaVersion(in: migrated), 5)
        XCTAssertEqual((retainedVersion4["schemaVersion"] as? NSNumber)?.intValue, 4)
        XCTAssertEqual(retainedVersion4["schedule"] as? String, version4Schedule)
        XCTAssertEqual(migrated["encrypted"] as? Bool, true)
        XCTAssertEqual(migrated["eventsEncrypted"] as? Bool, true)
        let releasedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let releasedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["customEvents"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(releasedClasses, classes)
        XCTAssertEqual(releasedEvents, events)
        XCTAssertEqual(migrated["legacySentinel"] as? String, "retain-v4-source")
    }

    func testFutureEncryptedMapCarrierIsNotDowngradedOrRewritten() async throws {
        let futureCarrier: [String: Any] = [
            "schemaVersion": 6,
            "schedule": "future-schedule",
            "events": "future-events",
            "futureSentinel": "keep-encrypted-map-v6"
        ]
        try await userDocument.setData([
            "uid": uid,
            "encrypted": futureCarrier
        ])

        await assertPermissionDenied("future encrypted-map carrier replacement") {
            try await self.userDocument.updateData(["encrypted": true])
        }

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("A future encrypted-map carrier must not be downgraded.")
        } catch CloudDataSchemaError.unsupportedVersion(let version) {
            XCTAssertEqual(version, 6)
        } catch {
            XCTFail("Expected unsupported encrypted-map schema, got \(error).")
        }

        let retained = try await documentData(userDocument)
        let encrypted = try XCTUnwrap(retained["encrypted"] as? [String: Any])
        XCTAssertEqual((encrypted["schemaVersion"] as? NSNumber)?.intValue, 6)
        XCTAssertEqual(encrypted["futureSentinel"] as? String, "keep-encrypted-map-v6")
        XCTAssertNil(retained["cloudDataV5"])
    }

    func testCompletedLegacySyncMigrationFencesStalePortWrites() async throws {
        try await seedCanonicalDocument()
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)

        let root = try await documentData(userDocument)
        XCTAssertEqual(
            (root["legacySyncMigrationVersion"] as? NSNumber)?.intValue,
            5
        )
        await assertPermissionDenied("post-migration sync schedule create") {
            try await self.userDocument.collection("sync").document("schedule")
                .setData(["payload": "stale-port-write"])
        }
        await assertPermissionDenied("post-migration sync state create") {
            try await self.userDocument.collection("sync").document("state")
                .setData(["classes": []])
        }
        await assertPermissionDenied("post-migration legacy session create") {
            try await self.userDocument.collection("sync").document("state")
                .collection("sessions").document("late-session")
                .setData([
                    "startedAt": Timestamp(date: Date()),
                    "endedAt": Timestamp(date: Date())
                ])
        }
    }

    func testNewerOldClientScheduleWriteWinsWithoutDestroyingCloudData() async throws {
        let canonicalClass = ClassItem(
            id: UUID(uuidString: "CA2536D9-F2B4-45F1-BE68-3F2E60E5B2BF")!,
            name: "Canonical Old",
            teacher: "Before",
            room: "1"
        )
        try await seedCanonicalDocument(
            classes: [canonicalClass],
            scheduleUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            eventsUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let before = try await documentData(userDocument)
        let beforeCloudData = try XCTUnwrap(before["cloudDataV5"] as? [String: Any])
        let eventsBlob = try XCTUnwrap(beforeCloudData["events"] as? String)

        let newerClass = ClassItem(
            id: UUID(uuidString: "C95B82D2-D9B0-464F-9B7A-48596B2E88E4")!,
            name: "Written by 1.21",
            teacher: "Newest",
            room: "2"
        )
        let oldClientData = try encryptedLegacyRoot(
            classes: [newerClass],
            events: [],
            lastUpdated: Date(timeIntervalSince1970: 1_700_010_000),
            includeEvents: false
        )
        try await userDocument.setData(oldClientData, merge: true)

        let loaded = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(loaded.0.first?.id, newerClass.id)
        XCTAssertEqual(loaded.0.first?.name, "Written by 1.21")

        let after = try await documentData(userDocument)
        let afterCloudData = try XCTUnwrap(after["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((afterCloudData["schemaVersion"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual(afterCloudData["events"] as? String, eventsBlob)
        XCTAssertEqual(afterCloudData["migrationSentinel"] as? String, "keep-cloud-data")
        XCTAssertEqual(after["encrypted"] as? Bool, true)
    }

    func testFutureCloudDataSchemaThrowsAndIsNotRewritten() async throws {
        let futureCloudData: [String: Any] = [
            "schemaVersion": 6,
            "schedule": "future-schedule",
            "theme": "future-theme",
            "isSecondLunch": "future-lunch",
            "events": "future-events",
            "migrationSentinel": "future-must-survive"
        ]
        var validLegacy = try encryptedLegacyRoot(
            classes: [ClassItem(name: "Do Not Downgrade", teacher: "Future", room: "6")],
            events: [],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        validLegacy["cloudData"] = futureCloudData
        try await userDocument.setData(validLegacy)

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("A future cloudData schema must not be interpreted or downgraded.")
        } catch {
            // Expected: the client cannot safely understand schema version 6.
        }

        let after = try await documentData(userDocument)
        let retained = try XCTUnwrap(after["cloudData"] as? [String: Any])
        XCTAssertEqual((retained["schemaVersion"] as? NSNumber)?.intValue, 6)
        XCTAssertEqual(retained["schedule"] as? String, "future-schedule")
        XCTAssertEqual(retained["theme"] as? String, "future-theme")
        XCTAssertEqual(retained["isSecondLunch"] as? String, "future-lunch")
        XCTAssertEqual(retained["events"] as? String, "future-events")
        XCTAssertEqual(retained["migrationSentinel"] as? String, "future-must-survive")

    }

    func testRulesPreserveFutureCanonicalV5Carrier() async throws {
        try await seedCanonicalDocument()
        // A future app may advance this reserved carrier in place. Older rules
        // and clients must never be able to downgrade it afterward.
        try await userDocument.updateData(["cloudDataV5.schemaVersion": 6])
        await assertPermissionDenied("future cloudDataV5 downgrade") {
            try await self.userDocument.updateData(["cloudDataV5.schemaVersion": 5])
        }
        let retained = try await documentData(userDocument)
        let canonical = try XCTUnwrap(retained["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((canonical["schemaVersion"] as? NSNumber)?.intValue, 6)
    }

    func testDirectEventSaveRejectsFutureSchemaWithoutPriorLoad() async throws {
        let canonicalEvent = CustomEvent(
            id: UUID(uuidString: "0A1B1CB5-BBB5-47F2-A775-F70B1823BE62")!,
            title: "Canonical Before Future Upgrade",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        try await seedCanonicalDocument(events: [canonicalEvent])
        let before = try await documentData(userDocument)
        let canonicalBefore = try XCTUnwrap(before["cloudDataV5"] as? [String: Any])

        let futureCloudData: [String: Any] = [
            "schemaVersion": 6,
            "events": "future-events-must-survive",
            "futureSentinel": "keep-v6"
        ]
        try await userDocument.setData(["cloudData": futureCloudData], merge: true)

        let localEvent = CustomEvent(
            id: UUID(uuidString: "94166735-F2C9-48A4-8BA1-04008EAFC0C2")!,
            title: "Stale Direct Save",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        do {
            // Intentionally do not load first. The transaction itself must
            // discover the future schema instead of relying on an in-memory
            // read fence left by a prior load/listener.
            try await CloudEventsDataManager().saveEvents([localEvent], for: uid)
            XCTFail("A direct event save must not write beside or downgrade schema 6.")
        } catch CloudDataSchemaError.unsupportedVersion(let version) {
            XCTAssertEqual(version, 6)
        } catch {
            XCTFail("Expected unsupported schema 6, got \(error).")
        }

        let after = try await documentData(userDocument)
        let retainedFuture = try XCTUnwrap(after["cloudData"] as? [String: Any])
        let retainedCanonical = try XCTUnwrap(after["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((retainedFuture["schemaVersion"] as? NSNumber)?.intValue, 6)
        XCTAssertEqual(retainedFuture["events"] as? String, "future-events-must-survive")
        XCTAssertEqual(retainedFuture["futureSentinel"] as? String, "keep-v6")
        XCTAssertEqual(retainedCanonical["events"] as? String, canonicalBefore["events"] as? String)
        XCTAssertEqual(
            (retainedCanonical["schemaVersion"] as? NSNumber)?.intValue,
            5
        )
    }

    func testCorruptVersion5RecoversFromValidLegacyRoot() async throws {
        let classID = UUID(uuidString: "483F8102-F28D-49E4-BDC3-0C48BD95086A")!
        let eventID = UUID(uuidString: "24E3F093-B89C-4F0C-B990-1993857173FC")!
        let legacyClass = ClassItem(
            id: classID,
            name: "Recovery Class",
            teacher: "Backup",
            room: "R"
        )
        let legacyEvent = CustomEvent(
            id: eventID,
            title: "Recovery Event",
            startTime: Time(h: 12, m: 0, s: 0),
            endTime: Time(h: 13, m: 0, s: 0),
            applicableDays: ["B2"]
        )
        var root = try encryptedLegacyRoot(
            classes: [legacyClass],
            events: [legacyEvent],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        root["cloudDataV5"] = corruptVersion5CloudData
        try await userDocument.setData(root)

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0.first?.id, classID)
        XCTAssertEqual(loadedEvents.first?.id, eventID)

        let recovered = try await documentData(userDocument)
        let cloudData = try XCTUnwrap(recovered["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((cloudData["schemaVersion"] as? NSNumber)?.intValue, 5)
        XCTAssertNotEqual(cloudData["schedule"] as? String, "not-valid-base64-schedule")
        XCTAssertNotEqual(cloudData["events"] as? String, "not-valid-base64-events")
        XCTAssertEqual(recovered["encrypted"] as? Bool, true)
        let corruptRecovery = try XCTUnwrap(
            recovered["migrationRecoveryCorruptV5"] as? [String: Any]
        )
        XCTAssertEqual(
            corruptRecovery["schedule"] as? String,
            "not-valid-base64-schedule"
        )
        XCTAssertEqual(
            corruptRecovery["events"] as? String,
            "not-valid-base64-events"
        )
        let releasedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(recovered["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        XCTAssertEqual(releasedClasses, [legacyClass])
    }

    func testCorruptVersion5WithoutValidRecoveryThrowsAndIsNotRewritten() async throws {
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": corruptVersion5CloudData
        ])

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("Corrupt canonical data without a valid recovery source must throw.")
        } catch {
            // Expected: silently replacing this payload with defaults loses data.
        }

        let after = try await documentData(userDocument)
        let retained = try XCTUnwrap(after["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((retained["schemaVersion"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual(retained["schedule"] as? String, "not-valid-base64-schedule")
        XCTAssertEqual(retained["theme"] as? String, "not-valid-base64-theme")
        XCTAssertEqual(retained["isSecondLunch"] as? String, "not-valid-base64-lunch")
        XCTAssertEqual(retained["events"] as? String, "not-valid-base64-events")
    }

    func testMalformedVersion5ContainerThrowsAndIsNeverReplacedWithDefaults() async throws {
        // A partial/invalid Firestore port can leave the reserved canonical
        // field with the wrong type. This must be treated as recoverable
        // corruption, not as an absent account that is safe to initialize.
        let retainedSentinel = "opaque-canonical-data-must-survive"
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": retainedSentinel
        ])

        do {
            try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
            XCTFail("Malformed canonical data must stop migration.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: no migration write occurred.
        } catch {
            XCTFail("Expected corrupt canonical schema, got \(error).")
        }

        let retained = try await documentData(userDocument)
        XCTAssertEqual(retained["cloudDataV5"] as? String, retainedSentinel)
    }

    func testPartialVersion5ScheduleFailsClosedInsteadOfBecomingEmpty() async throws {
        let originalClasses = [ClassItem(
            id: UUID(uuidString: "D844AC10-96FA-46B5-99D8-0F76435E511F")!,
            name: "Partial Port Class",
            teacher: "Must Survive",
            room: "V5"
        )]
        let scheduleBlob = try EncryptionService.shared.encrypt(
            CombinedSchedulePayloadFixture(
                classes: originalClasses,
                theme: ThemeColors.defaultTheme,
                isSecondLunch: [false, false]
            ),
            userId: uid
        )
        let eventsBlob = try EncryptionService.shared.encrypt(
            [CustomEvent](),
            userId: uid
        )
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": [
                "schemaVersion": 5,
                "schedule": scheduleBlob,
                "events": eventsBlob
            ]
        ])

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("A partial split-v5 schedule must not be replaced by defaults.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected.
        } catch {
            XCTFail("Expected corrupt partial schedule, got \(error).")
        }

        let retained = try await documentData(userDocument)
        let canonical = try XCTUnwrap(retained["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(canonical["schedule"] as? String, scheduleBlob)
        XCTAssertNil(canonical["theme"])
        XCTAssertNil(canonical["isSecondLunch"])
    }

    func testFractionalVersion5SchemaFailsClosedAndIsNotDowngraded() async throws {
        try await seedCanonicalDocument()
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        try await userDocument.updateData(["cloudDataV5.schemaVersion": 5.5])

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("A fractional canonical schema must not be truncated to version 5.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected.
        } catch {
            XCTFail("Expected corrupt fractional schema, got \(error).")
        }

        let retained = try await documentData(userDocument)
        let canonical = try XCTUnwrap(retained["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((canonical["schemaVersion"] as? NSNumber)?.doubleValue, 5.5)
    }

    func testWrongTypedLegacyScheduleFailsClosedWithoutCreatingCanonicalDefaults() async throws {
        let corruptClasses = "legacy-classes-must-not-be-coerced-to-empty"
        try await userDocument.setData([
            "uid": uid,
            "classes": corruptClasses,
            "theme": plaintextTheme,
            "isSecondLunch": [true, false]
        ])

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("Wrong-typed legacy classes must stop migration.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected.
        } catch {
            XCTFail("Expected corrupt legacy schedule, got \(error).")
        }

        let retained = try await documentData(userDocument)
        XCTAssertEqual(retained["classes"] as? String, corruptClasses)
        XCTAssertNil(retained["cloudDataV5"])
    }

    func testPartialLegacyThemeDoesNotAuthorizeEmptyClasses() async throws {
        try await userDocument.setData([
            "uid": uid,
            "theme": plaintextTheme,
            "lastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))
        ])

        _ = try await DataManager().loadFromCloud(for: uid)

        let migrated = try await documentData(userDocument)
        let canonical = try XCTUnwrap(migrated["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(canonical["scheduleInitialized"] as? Bool, false)
        XCTAssertEqual(migrated["scheduleInitialized"] as? Bool, false)
    }

    func testEventOnlyMigrationDoesNotPublishSyntheticEmptyScheduleToOldClients() async throws {
        let eventID = UUID(uuidString: "6490C75A-84C9-4A71-9BE3-DCB17CC14128")!
        try await userDocument.setData([
            "uid": uid,
            "customEvents": [plaintextEvent(
                id: eventID,
                title: "Event-only recovery",
                repeatPattern: RepeatPattern.none.rawValue
            )],
            "eventsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])

        _ = try await DataManager().loadFromCloud(for: uid)

        let migrated = try await documentData(userDocument)
        let canonical = try XCTUnwrap(migrated["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(canonical["scheduleInitialized"] as? Bool, false)
        XCTAssertNil(migrated["encrypted"])
        XCTAssertNil(migrated["classes"])
        XCTAssertNil(migrated["theme"])
        XCTAssertNil(migrated["isSecondLunch"])
        XCTAssertNotNil(migrated["customEvents"] as? String)
    }

    func testExplicitEmptyReleasedScheduleEstablishesAuthorityAfterSyntheticMigration() async throws {
        let eventID = UUID(uuidString: "29D6A358-1C5F-49E5-A6D1-E4B2DE7149EF")!
        try await userDocument.setData([
            "uid": uid,
            "customEvents": [plaintextEvent(
                id: eventID,
                title: "Keeps root alive",
                repeatPattern: RepeatPattern.none.rawValue
            )],
            "eventsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        _ = try await DataManager().loadFromCloud(for: uid)

        // This fixture only needs to be newer than the just-created synthetic
        // schedule. Keep it inside the accepted clock-skew window so this
        // authority test does not accidentally assert preservation of a
        // far-future imported timestamp (covered separately below).
        let releasedTimestamp = Date(
            timeIntervalSince1970: TimeInterval(Int(Date().timeIntervalSince1970) + 60)
        )
        try await userDocument.setData([
            "encrypted": true,
            "classes": try EncryptionService.shared.encrypt([ClassItem](), userId: uid),
            "theme": try EncryptionService.shared.encrypt(ThemeColors.defaultTheme, userId: uid),
            "isSecondLunch": try EncryptionService.shared.encrypt([false, false], userId: uid),
            "lastUpdated": Timestamp(date: releasedTimestamp)
        ], merge: true)

        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)

        let migrated = try await documentData(userDocument)
        let canonical = try XCTUnwrap(migrated["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(canonical["scheduleInitialized"] as? Bool, true)
        XCTAssertEqual(
            (canonical["scheduleUpdatedAt"] as? Timestamp)?.dateValue(),
            releasedTimestamp
        )
        let loader = DataManager()
        _ = try await loader.loadFromCloud(for: uid)
        XCTAssertTrue(loader.lastScheduleLoadWasAuthoritative)
    }

    func testNewerPartialSyncStatePreservesOlderCompleteScheduleFields() async throws {
        let classID = UUID(uuidString: "DFAF0681-0428-40F7-BE22-76A4CBB2B78B")!
        let originalClass = ClassItem(
            id: classID,
            name: "Must survive partial state",
            teacher: "Recovery",
            room: "101"
        )
        let newerTheme = ThemeColors(
            primary: "#AA1100FF",
            secondary: "#00BB22FF",
            tertiary: "#3344CCFF"
        )
        let rootTimestamp = Date().addingTimeInterval(-60)
        let newerPartialTimestamp = Date().addingTimeInterval(60)
        try await userDocument.setData([
            "uid": uid,
            "classes": [[
                "id": classID.uuidString,
                "name": originalClass.name,
                "teacher": originalClass.teacher,
                "room": originalClass.room
            ]],
            "theme": plaintextTheme,
            "isSecondLunch": [true, false],
            "lastUpdated": Timestamp(date: rootTimestamp)
        ])
        try await userDocument.collection("sync").document("state").setData([
            "theme": [
                "primary": newerTheme.primary,
                "secondary": newerTheme.secondary,
                "tertiary": newerTheme.tertiary
            ],
            "updatedAt": Timestamp(date: newerPartialTimestamp)
        ])

        let loaded = try await DataManager().loadFromCloud(for: uid)

        XCTAssertEqual(loaded.0, [originalClass])
        XCTAssertEqual(loaded.1, newerTheme)
        XCTAssertEqual(loaded.2, [true, false])
        let migrated = try await documentData(userDocument)
        let canonical = try XCTUnwrap(migrated["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(canonical["scheduleInitialized"] as? Bool, true)
    }

    func testCorruptVersion4CarrierFailsClosedWithoutWritingVersion5Defaults() async throws {
        let originalCarrier: [String: Any] = [
            "schemaVersion": 4,
            "schedule": "corrupt-version-four-schedule",
            "events": "corrupt-version-four-events",
            "scheduleUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            "eventsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
        try await userDocument.setData([
            "uid": uid,
            "encrypted": originalCarrier
        ])

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("A claimed but corrupt schema-4 carrier must stop migration.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected.
        } catch {
            XCTFail("Expected corrupt schema-4 payload, got \(error).")
        }

        let retained = try await documentData(userDocument)
        let carrier = try XCTUnwrap(retained["encrypted"] as? [String: Any])
        XCTAssertEqual(carrier["schedule"] as? String, originalCarrier["schedule"] as? String)
        XCTAssertEqual(carrier["events"] as? String, originalCarrier["events"] as? String)
        XCTAssertNil(retained["cloudDataV5"])
    }

    func testLegacyWeeklyEventAliasSurvivesMigration() async throws {
        let eventID = UUID(uuidString: "4420BBE8-A2CA-414B-B091-F16785C062D5")!
        try await userDocument.setData([
            "uid": uid,
            "classes": [],
            "theme": plaintextTheme,
            "isSecondLunch": [false, false],
            "customEvents": [plaintextEvent(
                id: eventID,
                title: "Historic Weekly Event",
                repeatPattern: "Weekly"
            )]
        ])

        let events = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, eventID)
        XCTAssertEqual(events.first?.repeatPattern, .weekly)

        let migrated = try await documentData(userDocument)
        let recovery = try XCTUnwrap(migrated["migrationRecoveryLegacy"] as? [String: Any])
        let retainedEvents = try XCTUnwrap(recovery["customEvents"] as? [[String: Any]])
        XCTAssertEqual(retainedEvents.first?["repeatPattern"] as? String, "Weekly")
        let releasedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["customEvents"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(releasedEvents.first?.repeatPattern, .weekly)
        XCTAssertEqual(canonicalSchemaVersion(in: migrated), 5)
    }

    func testCombinedVersion4ScheduleConvertsToSplitVersion5WithoutLosingEvents() async throws {
        let classID = UUID(uuidString: "7920D4B8-06C7-4866-96A9-8414036A49F8")!
        let eventID = UUID(uuidString: "C712FC30-513A-4735-BB04-5EF3E87F4C7A")!
        let classes = [ClassItem(
            id: classID,
            name: "Combined Payload Class",
            teacher: "Version Four",
            room: "404"
        )]
        let theme = ThemeColors(
            primary: "#123456FF",
            secondary: "#654321FF",
            tertiary: "#ABCDEF99"
        )
        let lunches = [true, false]
        let events = [CustomEvent(
            id: eventID,
            title: "Combined Payload Event",
            startTime: Time(h: 14, m: 0, s: 0),
            endTime: Time(h: 15, m: 0, s: 0),
            applicableDays: ["G2"]
        )]
        let combined = CombinedSchedulePayloadFixture(
            classes: classes,
            theme: theme,
            isSecondLunch: lunches
        )
        let combinedBlob = try EncryptionService.shared.encrypt(combined, userId: uid)
        let eventsBlob = try EncryptionService.shared.encrypt(events, userId: uid)
        let updatedAt = Timestamp(date: Date(timeIntervalSince1970: 1_700_020_000))

        try await userDocument.setData([
            "uid": uid,
            "encrypted": [
                "schemaVersion": 4,
                "schedule": combinedBlob,
                "events": eventsBlob,
                "scheduleUpdatedAt": updatedAt,
                "eventsUpdatedAt": updatedAt
            ]
        ])

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0, classes)
        XCTAssertEqual(loadedSchedule.1, theme)
        XCTAssertEqual(loadedSchedule.2, lunches)
        XCTAssertEqual(loadedEvents, events)

        let migrated = try await documentData(userDocument)
        let cloudData = try XCTUnwrap(migrated["cloudDataV5"] as? [String: Any])
        XCTAssertEqual((cloudData["schemaVersion"] as? NSNumber)?.intValue, 5)
        let splitClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let splitTheme = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["theme"] as? String),
            as: ThemeColors.self,
            userId: uid
        )
        let splitLunches = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["isSecondLunch"] as? String),
            as: [Bool].self,
            userId: uid
        )
        let migratedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(splitClasses, classes)
        XCTAssertEqual(splitTheme, theme)
        XCTAssertEqual(splitLunches, lunches)
        XCTAssertEqual(migratedEvents, events)

        let retainedVersion4 = try XCTUnwrap(migrated["migrationRecoveryV4"] as? [String: Any])
        XCTAssertEqual(retainedVersion4["schedule"] as? String, combinedBlob)
        XCTAssertEqual(retainedVersion4["events"] as? String, eventsBlob)
        XCTAssertEqual(migrated["encrypted"] as? Bool, true)
        XCTAssertEqual(migrated["eventsEncrypted"] as? Bool, true)
        let releasedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let releasedTheme = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["theme"] as? String),
            as: ThemeColors.self,
            userId: uid
        )
        let releasedLunches = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["isSecondLunch"] as? String),
            as: [Bool].self,
            userId: uid
        )
        let releasedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(migrated["customEvents"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(releasedClasses, classes)
        XCTAssertEqual(releasedTheme, theme)
        XCTAssertEqual(releasedLunches, lunches)
        XCTAssertEqual(releasedEvents, events)
    }

    func testReleasedClientCannotOverwriteVersion4CarrierBeforeAtomicMigration() async throws {
        let retainedClass = ClassItem(
            id: UUID(uuidString: "8DD72591-331C-40EE-85E5-F92ECBE278D6")!,
            name: "Version-four only copy",
            teacher: "Must survive",
            room: "V4"
        )
        let combined = CombinedSchedulePayloadFixture(
            classes: [retainedClass],
            theme: .defaultTheme,
            isSecondLunch: [false, false]
        )
        let carrier: [String: Any] = [
            "schemaVersion": 4,
            "schedule": try EncryptionService.shared.encrypt(combined, userId: uid),
            "events": try EncryptionService.shared.encrypt([CustomEvent](), userId: uid),
            "scheduleUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            "eventsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        try await userDocument.setData([
            "uid": uid,
            "encrypted": carrier
        ])

        await assertPermissionDenied("released client replacing v4 map") {
            try await userDocument.setData([
                "encrypted": true,
                "classes": try EncryptionService.shared.encrypt([ClassItem](), userId: uid),
                "theme": try EncryptionService.shared.encrypt(ThemeColors.defaultTheme, userId: uid),
                "isSecondLunch": try EncryptionService.shared.encrypt([false, false], userId: uid)
            ], merge: true)
        }
        var retained = try await documentData(userDocument)
        XCTAssertEqual(
            (retained["encrypted"] as? [String: Any])?["schedule"] as? String,
            carrier["schedule"] as? String
        )

        let migrated = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(migrated.0, [retainedClass])
        retained = try await documentData(userDocument)
        XCTAssertEqual(retained["encrypted"] as? Bool, true)
        XCTAssertEqual(
            (retained["migrationRecoveryV4"] as? [String: Any])?["schedule"] as? String,
            carrier["schedule"] as? String
        )
    }

    func testThemeOnlySaveAfterRemoteClassChangePreservesRemoteClasses() async throws {
        let initialClass = ClassItem(
            id: UUID(uuidString: "916DDF18-5A89-49CC-8C49-E3330EA85DA0")!,
            name: "Initial Local Class",
            teacher: "Local",
            room: "1"
        )
        let remoteClass = ClassItem(
            id: UUID(uuidString: "28C9A140-34D6-4717-BED7-97113E023BBA")!,
            name: "Remote Device Class",
            teacher: "Remote",
            room: "2"
        )
        let updatedTheme = ThemeColors(
            primary: "#AA0000FF",
            secondary: "#00AA00FF",
            tertiary: "#0000AAFF"
        )
        let initialDate = Date(timeIntervalSince1970: 1_700_030_000)
        try await seedCanonicalDocument(
            classes: [initialClass],
            scheduleUpdatedAt: initialDate,
            eventsUpdatedAt: initialDate
        )

        // Mirror the complete released-client representation so this fixture
        // models a document shared by old and new app versions.
        let seeded = try await documentData(userDocument)
        let seededCloud = try XCTUnwrap(seeded["cloudDataV5"] as? [String: Any])
        try await userDocument.setData([
            "encrypted": true,
            "classes": try XCTUnwrap(seededCloud["schedule"] as? String),
            "theme": try XCTUnwrap(seededCloud["theme"] as? String),
            "isSecondLunch": try XCTUnwrap(seededCloud["isSecondLunch"] as? String),
            "lastUpdated": Timestamp(date: initialDate)
        ], merge: true)

        let manager = DataManager()
        let initiallyLoaded = try await manager.loadFromCloud(for: uid)
        XCTAssertEqual(initiallyLoaded.0, [initialClass])

        // Another device changes only classes after this manager cached its
        // initial snapshot.
        let remoteDate = Date(timeIntervalSince1970: 1_700_031_000)
        let remoteClassesBlob = try EncryptionService.shared.encrypt([remoteClass], userId: uid)
        try await userDocument.setData([
            "classes": remoteClassesBlob,
            "lastUpdated": Timestamp(date: remoteDate),
            "cloudDataV5": [
                "schemaVersion": 5,
                "schedule": remoteClassesBlob,
                "scheduleUpdatedAt": Timestamp(date: remoteDate)
            ]
        ], merge: true)

        // The local caller still has the old class value and changes only the
        // theme. A field-scoped write must not put that stale class back.
        try await manager.saveToCloud(
            classes: [initialClass],
            theme: updatedTheme,
            isSecondLunch: [false, false],
            for: uid
        )

        let reloaded = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(reloaded.0, [remoteClass])
        XCTAssertEqual(reloaded.1, updatedTheme)
        XCTAssertEqual(reloaded.2, [false, false])

        let after = try await documentData(userDocument)
        let cloudData = try XCTUnwrap(after["cloudDataV5"] as? [String: Any])
        let storedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let storedTheme = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["theme"] as? String),
            as: ThemeColors.self,
            userId: uid
        )
        XCTAssertEqual(storedClasses, [remoteClass])
        XCTAssertEqual(storedTheme, updatedTheme)
    }

    func testThemeSavePreservesNewerOldClientRootOnlyClassWrite() async throws {
        let initialClass = ClassItem(
            id: UUID(uuidString: "0C5D323F-7D38-4C2A-9BFA-893C05D7A90D")!,
            name: "Initial Canonical Class",
            teacher: "Initial",
            room: "1"
        )
        let oldClientClass = ClassItem(
            id: UUID(uuidString: "C174089F-413A-477E-8DC5-A84243C3A811")!,
            name: "Old Client Root-Only Class",
            teacher: "Remote",
            room: "2"
        )
        let initialDate = Date(timeIntervalSince1970: 1_700_032_000)
        try await seedCanonicalDocument(
            classes: [initialClass],
            scheduleUpdatedAt: initialDate,
            eventsUpdatedAt: initialDate
        )

        let manager = DataManager()
        let initiallyLoaded = try await manager.loadFromCloud(for: uid)
        XCTAssertEqual(initiallyLoaded.0, [initialClass])

        // A released client knows only the top-level mirror. It changes the
        // class after this manager cached its base and leaves cloudDataV5 stale.
        let oldClientBlob = try EncryptionService.shared.encrypt([oldClientClass], userId: uid)
        try await userDocument.setData([
            "encrypted": true,
            "classes": oldClientBlob,
            "lastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_700_033_000))
        ], merge: true)

        let localTheme = ThemeColors(
            primary: "#123456FF",
            secondary: "#654321FF",
            tertiary: "#ABCDEF00"
        )
        try await manager.saveToCloud(
            classes: [initialClass],
            theme: localTheme,
            isSecondLunch: [false, false],
            for: uid
        )

        let root = try await documentData(userDocument)
        let cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let canonicalClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloud["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let releasedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(root["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let canonicalTheme = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloud["theme"] as? String),
            as: ThemeColors.self,
            userId: uid
        )
        XCTAssertEqual(canonicalClasses, [oldClientClass])
        XCTAssertEqual(releasedClasses, [oldClientClass])
        XCTAssertEqual(canonicalTheme, localTheme)
    }

    func testClearedClassTombstoneRejectsNewerReleasedRootResurrection() async throws {
        let classID = UUID(uuidString: "8D298A6D-509E-4F54-9F29-3E19B51DD4D1")!
        let populatedClass = ClassItem(
            id: classID,
            name: "Must Stay Cleared",
            teacher: "Released Client",
            room: "7"
        )
        let clearedClass = ClassItem(id: classID, name: "", teacher: "", room: "")
        try await seedCanonicalDocument(classes: [populatedClass])

        let deletingManager = DataManager()
        _ = try await deletingManager.loadFromCloud(for: uid)
        try await deletingManager.saveToCloud(
            classes: [clearedClass],
            theme: .defaultTheme,
            isSecondLunch: [false, false],
            for: uid
        )

        // A stale released build later uploads its pre-clear class array with
        // a clock that outranks canonical. The v5 tombstone must still win.
        let staleBlob = try EncryptionService.shared.encrypt([populatedClass], userId: uid)
        try await userDocument.setData([
            "encrypted": true,
            "classes": staleBlob,
            "lastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_900_000_000))
        ], merge: true)

        let reloaded = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(reloaded.0, [clearedClass])
        let root = try await documentData(userDocument)
        let cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertTrue((cloud["classTombstones"] as? [String] ?? []).contains(classID.uuidString))
    }

    func testEditedPreIDReleasedClassCanRestoreAfterRemoteClear() async throws {
        let classID = UUID(uuidString: "7E26868A-8312-43F5-846F-9B8FCBEF0434")!
        let original = ClassItem(
            id: classID,
            name: "Legacy Chemistry",
            teacher: "Teacher",
            room: "100"
        )
        let cleared = ClassItem(id: classID, name: "", teacher: "", room: "")
        let edited = ClassItem(
            id: classID,
            name: original.name,
            teacher: original.teacher,
            room: "Changed by old device"
        )
        try await seedCanonicalDocument(classes: [original])
        let deletingManager = DataManager()
        _ = try await deletingManager.loadFromCloud(for: uid)
        try await deletingManager.saveToCloud(
            classes: [cleared],
            theme: .defaultTheme,
            isSecondLunch: [false, false],
            for: uid
        )

        let preIDEdited = [[
            "name": edited.name,
            "teacher": edited.teacher,
            "room": edited.room
        ]]
        try await userDocument.setData([
            "encrypted": true,
            "classes": try EncryptionService.shared.encrypt(preIDEdited, userId: uid),
            "lastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_900_000_000))
        ], merge: true)

        let restored = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(restored.0, [edited])
        let root = try await documentData(userDocument)
        let cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertFalse(
            (cloud["classTombstones"] as? [String] ?? []).contains(classID.uuidString)
        )
        XCTAssertNil((cloud["classTombstoneBases"] as? [String: Any])?[classID.uuidString])
    }

    func testOfflineClassEditRacingRemoteClearPreservesTheEdit() async throws {
        let classID = UUID(uuidString: "D0A9DA7E-F8A5-4C75-83A5-D6912723A7E1")!
        let original = ClassItem(
            id: classID,
            name: "Original Class",
            teacher: "Original Teacher",
            room: "101"
        )
        let cleared = ClassItem(id: classID, name: "", teacher: "", room: "")
        var edited = original
        edited.room = "Offline Edit 202"
        try await seedCanonicalDocument(classes: [original])

        let offlineDevice = DataManager()
        _ = try await offlineDevice.loadFromCloud(for: uid)

        var root = try await documentData(userDocument)
        var cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let clearedBlob = try EncryptionService.shared.encrypt([cleared], userId: uid)
        cloud["schedule"] = clearedBlob
        cloud["classTombstones"] = [classID.uuidString]
        cloud["scheduleUpdatedAt"] = Timestamp(
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await userDocument.setData([
            "cloudDataV5": cloud,
            "encrypted": true,
            "classes": clearedBlob,
            "lastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_800_000_000))
        ], merge: true)

        try await offlineDevice.saveToCloud(
            classes: [edited],
            theme: .defaultTheme,
            isSecondLunch: [false, false],
            for: uid
        )

        root = try await documentData(userDocument)
        cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let committed = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloud["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        XCTAssertEqual(committed, [edited])
        XCTAssertFalse(
            (cloud["classTombstones"] as? [String] ?? []).contains(classID.uuidString)
        )
    }

    func testColdScheduleSaveCannotRestoreRemoteClassTombstone() async throws {
        let classID = UUID(uuidString: "50D4FB89-2EA2-4F85-A804-259AD4FB8DB5")!
        let stale = ClassItem(
            id: classID,
            name: "Stale cold-device class",
            teacher: "Must not return",
            room: "9"
        )
        let cleared = ClassItem(id: classID, name: "", teacher: "", room: "")
        var cloud = try encryptedMap(
            schemaVersion: 5,
            classes: [cleared],
            events: [],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        cloud["classTombstones"] = [classID.uuidString]
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": cloud
        ])

        // This manager never loaded a caller-visible baseline. Its local value
        // is an unchanged stale replay, not an explicit restore action.
        try await DataManager().saveToCloud(
            classes: [stale],
            theme: .defaultTheme,
            isSecondLunch: [false, false],
            for: uid
        )

        let root = try await documentData(userDocument)
        let storedCloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertTrue(
            (storedCloud["classTombstones"] as? [String] ?? []).contains(classID.uuidString)
        )
        let stored = try EncryptionService.shared.decrypt(
            try XCTUnwrap(storedCloud["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        XCTAssertEqual(stored, [cleared])
    }

    func testPreIDClientCannotResurrectClearedClassOrReplaceItsStableIdentity() async throws {
        let classID = UUID(uuidString: "DC61A1DA-7B91-485F-A814-3CA482B8144D")!
        let original = ClassItem(
            id: classID,
            name: "Legacy Biology",
            teacher: "Teacher",
            room: "301"
        )
        try await seedCanonicalDocument(classes: [original])
        _ = try await DataManager().loadFromCloud(for: uid)

        // Schedule 1.17 and earlier encoded class arrays without UUIDs. Model
        // an old device clearing its first class after schema 5 is already live.
        let clearedWithoutID = [["name": "", "teacher": "", "room": ""]]
        let clearedBlob = try EncryptionService.shared.encrypt(clearedWithoutID, userId: uid)
        try await userDocument.setData([
            "encrypted": true,
            "classes": clearedBlob,
            // This is the legitimate newer clear. Keep its ordering token
            // inside the trusted skew window; the deliberately far-future
            // stale replay below remains the clock-poisoning regression.
            "lastUpdated": Timestamp(date: Date().addingTimeInterval(60))
        ], merge: true)

        let afterClear = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(afterClear.0, [ClassItem(id: classID, name: "", teacher: "", room: "")])

        // A still-stale pre-ID device later replays the populated value. Its
        // missing UUID must be reconciled by position before tombstones apply.
        let staleWithoutID = [[
            "name": original.name,
            "teacher": original.teacher,
            "room": original.room
        ]]
        let staleBlob = try EncryptionService.shared.encrypt(staleWithoutID, userId: uid)
        try await userDocument.setData([
            "encrypted": true,
            "classes": staleBlob,
            "lastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_900_000_000))
        ], merge: true)

        let afterReplay = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(afterReplay.0, [ClassItem(id: classID, name: "", teacher: "", room: "")])
        let finalRoot = try await documentData(userDocument)
        let finalCloud = try XCTUnwrap(finalRoot["cloudDataV5"] as? [String: Any])
        XCTAssertTrue(
            (finalCloud["classTombstones"] as? [String] ?? []).contains(classID.uuidString)
        )
        let sanitizedReleasedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(finalRoot["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        XCTAssertEqual(
            sanitizedReleasedClasses,
            [ClassItem(id: classID, name: "", teacher: "", room: "")]
        )
    }

    func testClearedUsageStatsDoNotResurrectWhenMigrationMarkerIsRemoved() async throws {
        let embeddedSession: [String: Any] = [
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_600_000_000)),
            "endedAt": Timestamp(date: Date(timeIntervalSince1970: 1_600_000_120)),
            "appVersion": "1.17.3"
        ]
        try await seedCanonicalDocument()
        // Signing in starts the app's normal migration task. Settle it before
        // injecting a late pre-1.18 embedded snapshot; otherwise this test can
        // join the already-running empty migration and assert before the
        // root-change reconciliation begins.
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        try await userDocument.setData([
            "usageStats": ["sessions": [embeddedSession]]
        ], merge: true)

        let seededRoot = try await documentData(userDocument)
        let seededUsageStats = try XCTUnwrap(seededRoot["usageStats"] as? [String: Any])
        XCTAssertEqual(
            (seededUsageStats["sessions"] as? [[String: Any]])?.count,
            1
        )
        XCTAssertNil(seededRoot["usageSessionsClearedAt"])

        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        let initiallyMigratedRoot = try await documentData(userDocument)
        XCTAssertEqual(
            (initiallyMigratedRoot["usageSessionMigrationVersion"] as? NSNumber)?.intValue,
            5
        )
        XCTAssertNil(initiallyMigratedRoot["usageSessionsClearedAt"])
        var migratedSessions = try await userDocument.collection("sessions").getDocuments().documents
        XCTAssertEqual(migratedSessions.count, 1)

        try await DataManager().clearUsageStats(for: uid)
        migratedSessions = try await userDocument.collection("sessions").getDocuments().documents
        XCTAssertTrue(migratedSessions.isEmpty)
        let clearedRoot = try await documentData(userDocument)
        XCTAssertNotNil(clearedRoot["usageSessionsClearedAt"] as? Timestamp)
        let retainedUsageStats = try XCTUnwrap(clearedRoot["usageStats"] as? [String: Any])
        XCTAssertTrue((retainedUsageStats["sessions"] as? [[String: Any]] ?? []).isEmpty)

        try await userDocument.updateData([
            "usageSessionMigrationVersion": FieldValue.delete()
        ])
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)

        migratedSessions = try await userDocument.collection("sessions").getDocuments().documents
        XCTAssertTrue(migratedSessions.isEmpty)
        let rerunRoot = try await documentData(userDocument)
        XCTAssertEqual(
            (rerunRoot["usageSessionMigrationVersion"] as? NSNumber)?.intValue,
            5
        )
        XCTAssertNotNil(rerunRoot["usageSessionsClearedAt"] as? Timestamp)
    }

    func testStaleSessionAppendAfterClearIsIgnoredAndRulesRejectDirectResurrection() async throws {
        try await seedCanonicalDocument()
        let manager = DataManager()
        try await manager.clearUsageStats(for: uid)

        let staleSession = UsageSessionRecord(
            id: "stale-after-clear",
            startedAt: Date(timeIntervalSince1970: 1_600_000_000),
            endedAt: Date(timeIntervalSince1970: 1_600_000_120),
            appVersion: "1.17.3",
            lastPage: "home",
            pageDurations: [:],
            featureDurations: [:],
            featureViewCounts: [:],
            itemActionCounts: [:],
            newsTabDurations: [:],
            newsTabViewCounts: [:],
            notificationsEnabled: false,
            liveActivitiesEnabled: false,
            liveActivityActive: false
        )
        try await manager.appendUsageSessionToCloud(staleSession, for: uid)
        let staleSnapshot = try await userDocument.collection("sessions")
            .document(staleSession.id)
            .getDocument()
        XCTAssertFalse(staleSnapshot.exists)

        let directReference = userDocument.collection("sessions").document("direct-stale-write")
        do {
            try await directReference.setData([
                "id": "direct-stale-write",
                "startedAt": Timestamp(date: staleSession.startedAt),
                "endedAt": Timestamp(date: staleSession.endedAt)
            ])
            XCTFail("Firestore rules accepted a pre-clear session resurrection.")
        } catch {
            XCTAssertEqual((error as NSError).domain, FirestoreErrorDomain)
        }
        let rejectedDirectSnapshot = try await directReference.getDocument()
        XCTAssertFalse(rejectedDirectSnapshot.exists)
    }

    func testWrongTypedEmbeddedUsageCarrierCannotDeleteCanonicalHistory() async throws {
        try await seedCanonicalDocument()
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        let retainedSession = userDocument.collection("sessions").document("must-survive")
        try await retainedSession.setData([
            "id": "must-survive",
            "schemaVersion": 2,
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000)),
            "endedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_120))
        ])
        try await userDocument.setData([
            "usageStats": ["sessions": "corrupt-not-an-array"],
            "usageStatsUpdatedAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_900_000_000)
            )
        ], merge: true)

        do {
            try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
            XCTFail("Wrong-typed usage data must not be interpreted as Clear.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected.
        } catch {
            XCTFail("Expected corrupt usage carrier, got \(error).")
        }

        let retainedSnapshot = try await retainedSession.getDocument()
        XCTAssertTrue(retainedSnapshot.exists)
        let root = try await documentData(userDocument)
        XCTAssertNil(root["usageSessionsClearedAt"])
    }

    func testFractionalMigrationMarkerFailsClosedWithoutSkippingRecovery() async throws {
        let retainedClass = ClassItem(
            id: UUID(uuidString: "2CB43B2C-0E77-4BC8-B3BE-C4A96376635B")!,
            name: "Marker recovery class",
            teacher: "Must survive",
            room: "5"
        )
        var root = try encryptedLegacyRoot(
            classes: [retainedClass],
            events: [],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        root["legacySyncMigrationVersion"] = 5.5
        try await userDocument.setData(root)

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("A fractional completion marker must not skip recovery sources.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected.
        } catch {
            XCTFail("Expected corrupt migration marker, got \(error).")
        }

        let retained = try await documentData(userDocument)
        XCTAssertEqual(
            (retained["legacySyncMigrationVersion"] as? NSNumber)?.doubleValue,
            5.5
        )
        XCTAssertNil(retained["cloudDataV5"])
    }

    func testSessionSpanningClearDoesNotRestorePreClearUsage() async throws {
        try await seedCanonicalDocument()
        let manager = DataManager()
        try await manager.clearUsageStats(for: uid)

        let spanningSession = UsageSessionRecord(
            id: "spans-clear",
            startedAt: Date(timeIntervalSince1970: 1_600_000_000),
            endedAt: Date().addingTimeInterval(3_600),
            appVersion: "1.21.1",
            lastPage: "home",
            pageDurations: ["home": 600],
            featureDurations: ["classes": 300],
            featureViewCounts: ["classes": 4],
            itemActionCounts: ["class": ["edit": 2]],
            newsTabDurations: [:],
            newsTabViewCounts: [:],
            notificationsEnabled: true,
            liveActivitiesEnabled: true,
            liveActivityActive: false
        )
        try await manager.appendUsageSessionToCloud(spanningSession, for: uid)

        let snapshot = try await userDocument.collection("sessions")
            .document(spanningSession.id)
            .getDocument()
        XCTAssertFalse(snapshot.exists)
    }

    func testOldClientEventOnlyWriteReconcilesWithoutChangingSchedule() async throws {
        let scheduleClass = ClassItem(
            id: UUID(uuidString: "1609047F-4346-420D-AEE6-F30D05917F12")!,
            name: "Schedule Must Stay",
            teacher: "Unchanged",
            room: "S"
        )
        let oldEvent = CustomEvent(
            id: UUID(uuidString: "1D91DC36-180D-40F2-B4AE-A2ADEB15BB27")!,
            title: "Canonical Event",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        let newEvent = CustomEvent(
            id: UUID(uuidString: "2155AA20-E4E0-40DB-B87D-732A25A7199D")!,
            title: "Old Client Event Write",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        let canonicalDate = Date(timeIntervalSince1970: 1_700_040_000)
        try await seedCanonicalDocument(
            classes: [scheduleClass],
            events: [oldEvent],
            scheduleUpdatedAt: canonicalDate,
            eventsUpdatedAt: canonicalDate
        )
        let before = try await documentData(userDocument)
        let beforeCloud = try XCTUnwrap(before["cloudDataV5"] as? [String: Any])
        let scheduleBlob = try XCTUnwrap(beforeCloud["schedule"] as? String)
        let themeBlob = try XCTUnwrap(beforeCloud["theme"] as? String)
        let lunchBlob = try XCTUnwrap(beforeCloud["isSecondLunch"] as? String)

        let eventWriteDate = Timestamp(date: Date(timeIntervalSince1970: 1_700_041_000))
        let oldClientEventBlob = try EncryptionService.shared.encrypt([newEvent], userId: uid)
        try await userDocument.setData([
            "eventsEncrypted": true,
            "customEvents": oldClientEventBlob,
            "eventsLastUpdated": eventWriteDate
        ], merge: true)

        let loadedEvents = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(loadedEvents, [newEvent])
        XCTAssertEqual(loadedSchedule.0, [scheduleClass])

        let after = try await documentData(userDocument)
        let afterCloud = try XCTUnwrap(after["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(afterCloud["schedule"] as? String, scheduleBlob)
        XCTAssertEqual(afterCloud["theme"] as? String, themeBlob)
        XCTAssertEqual(afterCloud["isSecondLunch"] as? String, lunchBlob)
        XCTAssertEqual(afterCloud["migrationSentinel"] as? String, "keep-cloud-data")
        let reconciledEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(afterCloud["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(reconciledEvents, [newEvent])
    }

    func testDeletedEventTombstoneRejectsNewerReleasedRootResurrection() async throws {
        let deletedEvent = CustomEvent(
            id: UUID(uuidString: "F63C9071-5EA2-407E-81B5-B22452A24E48")!,
            title: "Must Stay Deleted",
            startTime: Time(h: 12, m: 0, s: 0),
            endTime: Time(h: 13, m: 0, s: 0),
            applicableDays: ["G2"]
        )
        try await seedCanonicalDocument(events: [deletedEvent])

        let deletingManager = CloudEventsDataManager()
        _ = try await deletingManager.loadEvents(for: uid)
        try await deletingManager.saveEvents([], for: uid)

        let staleBlob = try EncryptionService.shared.encrypt([deletedEvent], userId: uid)
        let staleDate = Timestamp(date: Date(timeIntervalSince1970: 1_900_000_000))
        try await userDocument.setData([
            "eventsEncrypted": true,
            "customEvents": staleBlob,
            "eventsUpdatedAt": staleDate,
            "eventsLastUpdated": staleDate
        ], merge: true)

        let reloaded = try await CloudEventsDataManager().loadEvents(for: uid)
        XCTAssertTrue(reloaded.isEmpty)
        let root = try await documentData(userDocument)
        let cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertTrue(
            (cloud["eventTombstones"] as? [String] ?? [])
                .contains(deletedEvent.id.uuidString)
        )
    }

    func testEditedReleasedEventCanRestoreAfterRemoteDelete() async throws {
        let original = CustomEvent(
            id: UUID(uuidString: "C6383E17-B800-4595-8E21-E3A59F4DE9F5")!,
            title: "Original released event",
            startTime: Time(h: 12, m: 0, s: 0),
            endTime: Time(h: 13, m: 0, s: 0),
            applicableDays: ["G2"]
        )
        var edited = original
        edited.title = "Edited on old device"
        try await seedCanonicalDocument(events: [original])
        let deletingManager = CloudEventsDataManager()
        _ = try await deletingManager.loadEvents(for: uid)
        try await deletingManager.saveEvents([], for: uid)

        let editedBlob = try EncryptionService.shared.encrypt([edited], userId: uid)
        let editedAt = Timestamp(date: Date(timeIntervalSince1970: 1_900_000_000))
        try await userDocument.setData([
            "eventsEncrypted": true,
            "customEvents": editedBlob,
            "eventsUpdatedAt": editedAt,
            "eventsLastUpdated": editedAt
        ], merge: true)

        let restored = try await CloudEventsDataManager().loadEvents(for: uid)
        XCTAssertEqual(restored, [edited])
        let root = try await documentData(userDocument)
        let cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertFalse(
            (cloud["eventTombstones"] as? [String] ?? [])
                .contains(original.id.uuidString)
        )
        XCTAssertNil((cloud["eventTombstoneBases"] as? [String: Any])?[original.id.uuidString])
    }

    func testOfflineEventEditRacingRemoteDeletePreservesTheEdit() async throws {
        let eventID = UUID(uuidString: "D6489D8D-F35E-4E4A-BE3A-63157C509B7B")!
        let original = CustomEvent(
            id: eventID,
            title: "Original Event",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        var edited = original
        edited.title = "Offline Edited Event"
        try await seedCanonicalDocument(events: [original])

        let offlineDevice = CloudEventsDataManager()
        _ = try await offlineDevice.loadEvents(for: uid)

        var root = try await documentData(userDocument)
        var cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let emptyBlob = try EncryptionService.shared.encrypt([CustomEvent](), userId: uid)
        cloud["events"] = emptyBlob
        cloud["eventTombstones"] = [eventID.uuidString]
        cloud["eventsUpdatedAt"] = Timestamp(
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await userDocument.setData([
            "cloudDataV5": cloud,
            "eventsEncrypted": true,
            "customEvents": emptyBlob,
            "eventsUpdatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_800_000_000)),
            "eventsLastUpdated": Timestamp(date: Date(timeIntervalSince1970: 1_800_000_000))
        ], merge: true)

        try await offlineDevice.saveEvents([edited], for: uid)

        root = try await documentData(userDocument)
        cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let committed = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloud["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(committed, [edited])
        XCTAssertFalse(
            (cloud["eventTombstones"] as? [String] ?? []).contains(eventID.uuidString)
        )
    }

    func testColdEventSaveCannotRestoreRemoteEventTombstone() async throws {
        let stale = CustomEvent(
            id: UUID(uuidString: "E8D891B0-D405-46E9-9E61-6586337B5D69")!,
            title: "Stale cold-device event",
            startTime: Time(h: 9, m: 0, s: 0),
            endTime: Time(h: 10, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        var cloud = try encryptedMap(
            schemaVersion: 5,
            classes: [],
            events: [],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        cloud["eventTombstones"] = [stale.id.uuidString]
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": cloud
        ])

        // No caller-visible load occurred on this manager. Its unchanged local
        // copy cannot be treated as an intentional resurrection.
        try await CloudEventsDataManager().saveEvents([stale], for: uid)

        let root = try await documentData(userDocument)
        let storedCloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertTrue(
            (storedCloud["eventTombstones"] as? [String] ?? [])
                .contains(stale.id.uuidString)
        )
        let stored = try EncryptionService.shared.decrypt(
            try XCTUnwrap(storedCloud["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertTrue(stored.isEmpty)
    }

    func testStaleSyncScheduleAndEventsCannotOutrankNewerRoot() async throws {
        let rootClass = ClassItem(
            id: UUID(uuidString: "7B7F079E-21B2-4AD4-8D77-A1210B00BE14")!,
            name: "Newer Root Class",
            teacher: "Root",
            room: "N"
        )
        let staleClass = ClassItem(
            id: UUID(uuidString: "5FD2F3BB-30AE-4E73-9832-22A15176F95D")!,
            name: "Stale Sync Class",
            teacher: "Sync",
            room: "O"
        )
        let rootEvent = CustomEvent(
            id: UUID(uuidString: "115E7EDB-5B2D-4BDA-B3A1-D9449A1FCA65")!,
            title: "Newer Root Event",
            startTime: Time(h: 12, m: 0, s: 0),
            endTime: Time(h: 13, m: 0, s: 0),
            applicableDays: ["G2"]
        )
        let staleEvent = CustomEvent(
            id: UUID(uuidString: "56FA216E-18E0-4594-91B4-01B829E4953D")!,
            title: "Stale Sync Event",
            startTime: Time(h: 14, m: 0, s: 0),
            endTime: Time(h: 15, m: 0, s: 0),
            applicableDays: ["B2"]
        )
        let rootDate = Date(timeIntervalSince1970: 1_700_050_000)
        try await userDocument.setData(try encryptedLegacyRoot(
            classes: [rootClass],
            events: [rootEvent],
            lastUpdated: rootDate
        ))

        let staleDate = Timestamp(date: Date(timeIntervalSince1970: 1_600_000_000))
        let staleSchedulePayload = CombinedSchedulePayloadFixture(
            classes: [staleClass],
            theme: ThemeColors.defaultTheme,
            isSecondLunch: [true, true]
        )
        let syncSchedule = userDocument.collection("sync").document("schedule")
        let syncEvents = userDocument.collection("sync").document("events")
        try await syncSchedule.setData([
            "payload": try EncryptionService.shared.encrypt(staleSchedulePayload, userId: uid),
            "updatedAt": staleDate
        ])
        try await syncEvents.setData([
            "payload": try EncryptionService.shared.encrypt([staleEvent], userId: uid),
            "updatedAt": staleDate
        ])

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0, [rootClass])
        XCTAssertEqual(loadedSchedule.2, [false, false])
        XCTAssertEqual(loadedEvents, [rootEvent])

        let migrated = try await documentData(userDocument)
        let cloudData = try XCTUnwrap(migrated["cloudDataV5"] as? [String: Any])
        let migratedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let migratedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloudData["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(migratedClasses, [rootClass])
        XCTAssertEqual(migratedEvents, [rootEvent])
        let retainedSyncSchedule = try await syncSchedule.getDocument()
        let retainedSyncEvents = try await syncEvents.getDocument()
        XCTAssertTrue(retainedSyncSchedule.exists)
        XCTAssertTrue(retainedSyncEvents.exists)
    }

    func testConcurrentScheduleAndEventWritesPreserveBothDomains() async throws {
        try await seedCanonicalDocument()
        let classes = [ClassItem(name: "Concurrent Class", teacher: "A", room: "2")]
        let event = CustomEvent(
            title: "Concurrent Event",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )

        async let scheduleWrite: Void = DataManager().saveToCloud(
            classes: classes,
            theme: .defaultTheme,
            isSecondLunch: [false, true],
            for: uid
        )
        async let eventWrite: Void = CloudEventsDataManager.shared.saveEvents([event], for: uid)
        _ = try await (scheduleWrite, eventWrite)

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager.shared.loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0.first?.name, "Concurrent Class")
        XCTAssertEqual(loadedSchedule.2, [false, true])
        XCTAssertEqual(loadedEvents.first?.id, event.id)
    }

    func testStaleEventAddMergesWithRemoteDeviceAdd() async throws {
        let manager = CloudEventsDataManager()
        try await seedCanonicalDocument()
        let initiallyLoaded = try await manager.loadEvents(for: uid)
        XCTAssertEqual(initiallyLoaded, [])

        let remoteEvent = CustomEvent(
            id: UUID(uuidString: "9E21E996-98C1-4B42-B54C-44E467A91772")!,
            title: "Remote Device Add",
            startTime: Time(h: 9, m: 0, s: 0),
            endTime: Time(h: 10, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        var root = try await documentData(userDocument)
        var cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let remoteBlob = try EncryptionService.shared.encrypt([remoteEvent], userId: uid)
        let remoteDate = Timestamp(date: Date(timeIntervalSince1970: 1_700_061_000))
        cloud["events"] = remoteBlob
        cloud["eventsUpdatedAt"] = remoteDate
        try await userDocument.setData([
            "cloudDataV5": cloud,
            "eventsEncrypted": true,
            "customEvents": remoteBlob,
            "eventsUpdatedAt": remoteDate,
            "eventsLastUpdated": remoteDate
        ], merge: true)

        let localEvent = CustomEvent(
            id: UUID(uuidString: "7A94A3E6-D6C3-45A4-A0DB-E7D9B9526AE3")!,
            title: "Stale Local Device Add",
            startTime: Time(h: 11, m: 0, s: 0),
            endTime: Time(h: 12, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        try await manager.saveEvents([localEvent], for: uid)

        root = try await documentData(userDocument)
        cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let merged = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloud["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(Set(merged.map(\.id)), Set([localEvent.id, remoteEvent.id]))
    }

    func testOfflineWriteCommitsAfterNetworkReturns() async throws {
        try await seedCanonicalDocument()
        let firestore = Firestore.firestore()
        try await firestore.disableNetwork()
        var completed = false
        let save = Task { @MainActor in
            try await DataManager().saveToCloud(
                classes: [ClassItem(name: "Offline Class", teacher: "B", room: "3")],
                theme: .defaultTheme,
                isSecondLunch: [true, true],
                for: uid
            )
            completed = true
        }

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(completed)
        try await firestore.enableNetwork()
        try await save.value
        XCTAssertTrue(completed)
        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(loadedSchedule.0.first?.name, "Offline Class")
    }

    func testCancelledListenerStopsReceivingRemoteChanges() async throws {
        try await seedCanonicalDocument()
        let manager = DataManager()
        let initial = expectation(description: "Initial snapshot")
        var deliveries = 0
        let observation = manager.observeSchedule(for: uid) { result in
            if case .success = result {
                deliveries += 1
                initial.fulfill()
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        observation.cancel()
        let countAfterCancellation = deliveries

        try await DataManager().saveToCloud(
            classes: [ClassItem(name: "After Cancel", teacher: "C", room: "4")],
            theme: .defaultTheme,
            isSecondLunch: [false, false],
            for: uid
        )
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(deliveries, countAfterCancellation)
    }

    func testLiveListenersDeliverRootDeletionAndOlderRestoredData() async throws {
        let initialClass = ClassItem(
            name: "Initial Listener Class",
            teacher: "Initial Teacher",
            room: "101"
        )
        let restoredClass = ClassItem(
            name: "Restored Older Class",
            teacher: "Restored Teacher",
            room: "202"
        )
        let initialEvent = CustomEvent(
            title: "Initial Listener Event",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        let restoredEvent = CustomEvent(
            title: "Restored Older Event",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        let initialTimestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let restoredOlderTimestamp = Date(timeIntervalSince1970: 1_600_000_000)

        try await seedCanonicalDocument(
            classes: [initialClass],
            events: [initialEvent],
            scheduleUpdatedAt: initialTimestamp,
            eventsUpdatedAt: initialTimestamp
        )

        // Finish the normal migration/released-mirror path before testing the
        // listener lifecycle. This keeps the assertion focused on root
        // deletion/restoration rather than racing first-load migration.
        let scheduleManager = DataManager()
        let eventManager = CloudEventsDataManager()
        let loadedSchedule = try await scheduleManager.loadFromCloud(for: uid)
        let loadedEvents = try await eventManager.loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0.first?.name, initialClass.name)
        XCTAssertEqual(loadedEvents.first?.title, initialEvent.title)

        let initialSchedule = expectation(description: "Initial schedule listener value")
        let deletedSchedule = expectation(description: "Deleted schedule listener value")
        let restoredSchedule = expectation(description: "Restored older schedule listener value")
        let initialEvents = expectation(description: "Initial event listener value")
        let deletedEvents = expectation(description: "No destructive empty event listener value")
        deletedEvents.isInverted = true
        let restoredEvents = expectation(description: "Restored older event listener value")
        var scheduleDeletionDeliveries = 0
        var eventDeletionDeliveries = 0

        let scheduleObservation = scheduleManager.observeSchedule(for: uid) { result in
            switch result {
            case .success(let value):
                if value.0.first?.name == initialClass.name {
                    initialSchedule.fulfill()
                } else if value.0.isEmpty, !value.3 {
                    scheduleDeletionDeliveries += 1
                    XCTAssertEqual(value.1, .defaultTheme)
                    XCTAssertEqual(value.2, [false, false])
                    if scheduleDeletionDeliveries == 1 {
                        deletedSchedule.fulfill()
                    }
                } else if value.0.first?.name == restoredClass.name {
                    XCTAssertTrue(value.3)
                    restoredSchedule.fulfill()
                }
            case .failure(let error):
                XCTFail("Schedule listener failed: \(error)")
            }
        }
        let eventObservation = try XCTUnwrap(
            eventManager.observeEvents(for: uid) { result in
                switch result {
                case .success(let events):
                    if events.first?.title == initialEvent.title {
                        initialEvents.fulfill()
                    } else if events.isEmpty {
                        eventDeletionDeliveries += 1
                        if eventDeletionDeliveries == 1 {
                            deletedEvents.fulfill()
                        }
                    } else if events.first?.title == restoredEvent.title {
                        restoredEvents.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Event listener failed: \(error)")
                }
            }
        )
        defer {
            scheduleObservation.cancel()
            eventObservation.cancel()
        }

        await fulfillment(of: [initialSchedule, initialEvents], timeout: 5)

        // Root deletes are permanently denied to app clients. The emulator's
        // owner token models the Admin SDK worker/backend for this lifecycle
        // fixture and lets the listeners observe a genuine server deletion.
        try await emulatorAdminDeleteDocument(userDocument)
        await fulfillment(of: [deletedSchedule], timeout: 5)
        await fulfillment(of: [deletedEvents], timeout: 0.5)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(scheduleDeletionDeliveries, 1)
        XCTAssertEqual(eventDeletionDeliveries, 0)

        try await seedCanonicalDocument(
            classes: [restoredClass],
            events: [restoredEvent],
            scheduleUpdatedAt: restoredOlderTimestamp,
            eventsUpdatedAt: restoredOlderTimestamp
        )
        await fulfillment(of: [restoredSchedule, restoredEvents], timeout: 5)
    }

    func testScheduleOnlyRootRecreationRecoversEstablishedLocalEvents() async throws {
        let scheduleClass = ClassItem(
            name: "Recreated Schedule",
            teacher: "Recovery Teacher",
            room: "R1"
        )
        var scheduleOnlyCloud = try encryptedMap(
            schemaVersion: 5,
            classes: [scheduleClass],
            events: [],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        scheduleOnlyCloud.removeValue(forKey: "events")
        scheduleOnlyCloud.removeValue(forKey: "eventsUpdatedAt")
        scheduleOnlyCloud["scheduleInitialized"] = true
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": scheduleOnlyCloud
        ])

        let localEvent = CustomEvent(
            id: UUID(uuidString: "9750F374-7D07-428D-A52E-8B35ABF5160D")!,
            title: "Established Local Recovery",
            startTime: Time(h: 9, m: 0, s: 0),
            endTime: Time(h: 10, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        let (eventsManager, authManager) = try establishedEventsContext(
            localEvents: [localEvent]
        )

        eventsManager.loadFromCloud(using: authManager)
        await eventsManager.refreshCloudSync()

        XCTAssertEqual(eventsManager.events, [localEvent])
        var root = try await documentData(userDocument)
        var cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(cloud["eventsInitialized"] as? Bool, false)
        XCTAssertNil(root["customEvents"])
        await eventsManager.flushCloudSync()

        let recoveredState = try await CloudEventsDataManager().loadEventState(for: uid)
        XCTAssertTrue(recoveredState.isAuthoritative)
        XCTAssertEqual(recoveredState.events, [localEvent])
        root = try await documentData(userDocument)
        cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        XCTAssertEqual(cloud["eventsInitialized"] as? Bool, true)
    }

    func testAuthoritativeEmptyEventsStillDeletesEstablishedLocalCopy() async throws {
        try await seedCanonicalDocument(events: [])
        var root = try await documentData(userDocument)
        var cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        cloud["eventsInitialized"] = true
        try await userDocument.setData(["cloudDataV5": cloud], merge: true)

        let staleLocalEvent = CustomEvent(
            id: UUID(uuidString: "F5AE44F3-79F8-43F7-B697-FF93DAE13431")!,
            title: "Must Not Resurrect",
            startTime: Time(h: 11, m: 0, s: 0),
            endTime: Time(h: 12, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        let (eventsManager, authManager) = try establishedEventsContext(
            localEvents: [staleLocalEvent]
        )

        eventsManager.loadFromCloud(using: authManager)
        await eventsManager.refreshCloudSync()
        await eventsManager.flushCloudSync()

        XCTAssertTrue(eventsManager.events.isEmpty)
        let loadedState = try await CloudEventsDataManager().loadEventState(for: uid)
        XCTAssertTrue(loadedState.isAuthoritative)
        XCTAssertTrue(loadedState.events.isEmpty)
        root = try await documentData(userDocument)
        cloud = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let storedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(cloud["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertTrue(storedEvents.isEmpty)
    }

    func testAccountDeletionRequestIsAtomicDurableAndFencesMarkedAccount() async throws {
        try await seedCanonicalDocument()
        let session = userDocument.collection("sessions").document("retained-session")
        let syncState = userDocument.collection("sync").document("state")
        try await session.setData([
            "id": "retained-session",
            "startedAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))
        ])
        try await syncState.setData(["uid": uid, "fixture": "retained-sync"])

        let malformedMarker: [String: Any] = [
            "state": "requested",
            "workflowVersion": 1,
            "requestedAt": FieldValue.serverTimestamp(),
            "unexpected": true
        ]
        let malformedBatch = Firestore.firestore().batch()
        malformedBatch.updateData(
            ["accountDeletion": malformedMarker],
            forDocument: userDocument
        )
        malformedBatch.setData(malformedMarker, forDocument: deletionRequestDocument)
        await assertPermissionDenied("malformed deletion pair") {
            try await malformedBatch.commit()
        }

        let unpairedMarker: [String: Any] = [
            "state": "requested",
            "workflowVersion": 1,
            "requestedAt": FieldValue.serverTimestamp()
        ]
        await assertPermissionDenied("unpaired root tombstone") {
            try await self.userDocument.updateData([
                "accountDeletion": unpairedMarker
            ])
        }
        await assertPermissionDenied("unpaired external request") {
            try await self.deletionRequestDocument.setData(unpairedMarker)
        }

        try await DataManager().requestUserDataDeletion(for: uid)

        // The request document remains owner-readable so a retry can observe
        // the already-committed workflow, but it cannot be listed or mutated.
        let request = try await deletionRequestDocument.getDocument()
        let requestData = try XCTUnwrap(request.data())
        XCTAssertEqual(requestData["state"] as? String, "requested")
        XCTAssertEqual((requestData["workflowVersion"] as? NSNumber)?.intValue, 1)
        XCTAssertNotNil(requestData["requestedAt"] as? Timestamp)

        let adminRoot = try await emulatorAdminDocumentFields(userDocument)
        let embeddedMarker = try XCTUnwrap(
            emulatorMapFields(adminRoot["accountDeletion"])
        )
        XCTAssertEqual(emulatorString(embeddedMarker["state"]), "requested")
        XCTAssertEqual(emulatorInteger(embeddedMarker["workflowVersion"]), 1)
        XCTAssertNotNil(emulatorTimestamp(embeddedMarker["requestedAt"]))
        let retainedSession = try await emulatorAdminDocumentFields(session)
        let retainedSyncState = try await emulatorAdminDocumentFields(syncState)
        XCTAssertFalse(retainedSession.isEmpty)
        XCTAssertFalse(retainedSyncState.isEmpty)

        await assertPermissionDenied("marked root read") {
            _ = try await self.userDocument.getDocument()
        }
        await assertPermissionDenied("marked root write") {
            try await self.userDocument.updateData(["postRequestWrite": true])
        }
        await assertPermissionDenied("marked root delete") {
            try await self.userDocument.delete()
        }
        await assertPermissionDenied("marked session read") {
            _ = try await session.getDocument()
        }
        await assertPermissionDenied("marked session write") {
            try await session.setData(["postRequestWrite": true], merge: true)
        }
        await assertPermissionDenied("marked session delete") {
            try await session.delete()
        }
        await assertPermissionDenied("marked sync read") {
            _ = try await syncState.getDocument()
        }
        await assertPermissionDenied("marked sync write") {
            try await syncState.setData(["postRequestWrite": true], merge: true)
        }
        await assertPermissionDenied("request update") {
            try await self.deletionRequestDocument.updateData(["state": "complete"])
        }
        await assertPermissionDenied("request delete") {
            try await self.deletionRequestDocument.delete()
        }
        await assertPermissionDenied("request collection list") {
            _ = try await Firestore.firestore()
                .collection("accountDeletionRequests")
                .getDocuments()
        }

        // Even if an operational mistake removes the embedded tombstone, the
        // durable request prevents a still-valid client token from recreating
        // the user root. Only the backend may repair that minimal root.
        try await emulatorAdminDeleteDocument(userDocument)
        await assertPermissionDenied("orphan sync read after durable request") {
            _ = try await syncState.getDocument()
        }
        await assertPermissionDenied("orphan session read after durable request") {
            _ = try await session.getDocument()
        }
        await assertPermissionDenied("root recreation after durable request") {
            try await self.userDocument.setData(["uid": self.uid])
        }
    }

    func testRulesDenyRootAndSyncDeletesAndLimitSessionDeletesToClearCutoff() async throws {
        try await seedCanonicalDocument()
        let syncState = userDocument.collection("sync").document("state")
        try await syncState.setData(["uid": uid, "fixture": "delete-fence"])

        let cutoff = Date(timeIntervalSince1970: 1_700_000_100)
        let oldStartedAt = Timestamp(date: cutoff.addingTimeInterval(-60))
        let newStartedAt = Timestamp(date: cutoff.addingTimeInterval(60))
        let canonicalOld = userDocument.collection("sessions").document("canonical-old")
        let canonicalNew = userDocument.collection("sessions").document("canonical-new")
        let legacySessions = syncState.collection("sessions")
        let legacyOld = legacySessions.document("legacy-old")
        let legacyNew = legacySessions.document("legacy-new")

        for reference in [canonicalOld, legacyOld] {
            try await reference.setData([
                "id": reference.documentID,
                "startedAt": oldStartedAt
            ])
        }
        for reference in [canonicalNew, legacyNew] {
            try await reference.setData([
                "id": reference.documentID,
                "startedAt": newStartedAt
            ])
        }

        await assertPermissionDenied("root delete") {
            try await self.userDocument.delete()
        }
        await assertPermissionDenied("sync delete") {
            try await syncState.delete()
        }
        await assertPermissionDenied("session delete without clear tombstone") {
            try await canonicalOld.delete()
        }

        try await userDocument.updateData([
            "usageSessionsClearedAt": Timestamp(date: cutoff)
        ])
        await assertPermissionDenied("legacy dotted session resurrection after clear") {
            try await self.userDocument.setData([
                "usageStats.sessions": [[
                    "startedAt": oldStartedAt,
                    "endedAt": Timestamp(date: cutoff)
                ]]
            ], merge: true)
        }
        try await canonicalOld.delete()
        try await legacyOld.delete()
        await assertPermissionDenied("post-cutoff canonical session delete") {
            try await canonicalNew.delete()
        }
        await assertPermissionDenied("post-cutoff legacy session delete") {
            try await legacyNew.delete()
        }

        let canonicalOldAfterClear = try await canonicalOld.getDocument()
        let legacyOldAfterClear = try await legacyOld.getDocument()
        let canonicalNewAfterClear = try await canonicalNew.getDocument()
        let legacyNewAfterClear = try await legacyNew.getDocument()
        let rootAfterClear = try await userDocument.getDocument()
        let syncAfterClear = try await syncState.getDocument()
        XCTAssertFalse(canonicalOldAfterClear.exists)
        XCTAssertFalse(legacyOldAfterClear.exists)
        XCTAssertTrue(canonicalNewAfterClear.exists)
        XCTAssertTrue(legacyNewAfterClear.exists)
        XCTAssertTrue(rootAfterClear.exists)
        XCTAssertTrue(syncAfterClear.exists)
    }

    func testUnreadableReleasedMirrorsAreRepairedFromHealthyCanonicalData() async throws {
        let retainedClass = ClassItem(name: "Canonical Mirror Recovery", teacher: "Retained", room: "R1")
        let retainedEvent = CustomEvent(
            title: "Canonical Event Recovery",
            startTime: Time(h: 9, m: 0, s: 0),
            endTime: Time(h: 10, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        try await seedCanonicalDocument(classes: [retainedClass], events: [retainedEvent])
        let older = Timestamp(date: Date(timeIntervalSince1970: 1_600_000_000))
        try await userDocument.setData([
            "encrypted": true,
            "classes": "complete-type-but-corrupt-ciphertext",
            "theme": "complete-type-but-corrupt-theme",
            "isSecondLunch": "complete-type-but-corrupt-lunch",
            "lastUpdated": older,
            "eventsEncrypted": true,
            "customEvents": "complete-type-but-corrupt-events",
            "eventsUpdatedAt": older,
            "eventsLastUpdated": older
        ], merge: true)

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager().loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0, [retainedClass])
        XCTAssertEqual(loadedEvents, [retainedEvent])
        let repaired = try await documentData(userDocument)
        let repairedClasses = try EncryptionService.shared.decrypt(
            try XCTUnwrap(repaired["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let repairedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(repaired["customEvents"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(repairedClasses, [retainedClass])
        XCTAssertEqual(repairedEvents, [retainedEvent])
    }

    func testDualSchema5CarriersReconcileEachDomainByTimestamp() async throws {
        let canonicalClass = ClassItem(name: "Newer canonical class", teacher: "C", room: "1")
        let transitionalClass = ClassItem(name: "Older transitional class", teacher: "T", room: "2")
        let canonicalEvent = CustomEvent(
            title: "Older canonical event",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        let transitionalEvent = CustomEvent(
            title: "Newer transitional event",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_750_000_000)
        var canonical = try encryptedMap(
            schemaVersion: 5,
            classes: [canonicalClass],
            events: [canonicalEvent],
            updatedAt: newer
        )
        canonical["eventsUpdatedAt"] = Timestamp(date: older)
        var transitional = try encryptedMap(
            schemaVersion: 5,
            classes: [transitionalClass],
            events: [transitionalEvent],
            updatedAt: older
        )
        transitional["eventsUpdatedAt"] = Timestamp(date: newer)
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": canonical,
            "cloudData": transitional
        ])

        let loadedSchedule = try await DataManager().loadFromCloud(for: uid)
        let loadedEvents = try await CloudEventsDataManager().loadEvents(for: uid)
        XCTAssertEqual(loadedSchedule.0, [canonicalClass])
        XCTAssertEqual(loadedEvents, [transitionalEvent])
        let root = try await documentData(userDocument)
        let consolidated = try XCTUnwrap(root["cloudDataV5"] as? [String: Any])
        let storedEvents = try EncryptionService.shared.decrypt(
            try XCTUnwrap(consolidated["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(storedEvents, [transitionalEvent])
    }

    func testConflictingDualSchema5CarriersWithEqualTimestampsFailClosed() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let canonical = try encryptedMap(
            schemaVersion: 5,
            classes: [ClassItem(name: "Canonical claimant", teacher: "A", room: "1")],
            events: [],
            updatedAt: timestamp
        )
        let transitional = try encryptedMap(
            schemaVersion: 5,
            classes: [ClassItem(name: "Transitional claimant", teacher: "B", room: "2")],
            events: [],
            updatedAt: timestamp
        )
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": canonical,
            "cloudData": transitional
        ])
        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("Equal-time conflicting schema-5 carriers must not pick a winner.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: both source maps remain recoverable.
        }
        let retained = try await documentData(userDocument)
        XCTAssertEqual(
            (retained["cloudDataV5"] as? [String: Any])?["schedule"] as? String,
            canonical["schedule"] as? String
        )
        XCTAssertEqual(
            (retained["cloudData"] as? [String: Any])?["schedule"] as? String,
            transitional["schedule"] as? String
        )
    }

    func testRepeatedVersion4MigrationRefreshesRecoverySlotAndKeepsNewestData() async throws {
        let firstClass = ClassItem(name: "First v4 generation", teacher: "One", room: "1")
        let secondClass = ClassItem(name: "Second v4 generation", teacher: "Two", room: "2")
        let first = try encryptedMap(
            schemaVersion: 4,
            classes: [firstClass],
            events: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let second = try encryptedMap(
            schemaVersion: 4,
            classes: [secondClass],
            events: [],
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        try await userDocument.setData(["uid": uid, "encrypted": first])
        let firstLoad = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(firstLoad.0, [firstClass])

        try await userDocument.setData(["encrypted": second], merge: true)
        let secondLoad = try await DataManager().loadFromCloud(for: uid)
        XCTAssertEqual(secondLoad.0, [secondClass])
        let migrated = try await documentData(userDocument)
        let recovery = try XCTUnwrap(migrated["migrationRecoveryV4"] as? [String: Any])
        XCTAssertEqual(recovery["schedule"] as? String, second["schedule"] as? String)
        XCTAssertEqual(migrated["encrypted"] as? Bool, true)
    }

    func testFutureUsageSessionSchemaIsNeverDowngradedByMigrationOrAppend() async throws {
        try await seedCanonicalDocument()
        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let future = userDocument.collection("sessions").document("future-session")
        try await future.setData([
            "id": "future-session",
            "schemaVersion": 7,
            "startedAt": Timestamp(date: startedAt),
            "endedAt": Timestamp(date: startedAt.addingTimeInterval(60)),
            "futureSentinel": "must-survive"
        ])
        try await userDocument.setData([
            "usageStats": ["sessions": [[
                "id": "future-session",
                "schemaVersion": 2,
                "startedAt": Timestamp(date: startedAt),
                "endedAt": Timestamp(date: startedAt.addingTimeInterval(120))
            ]]],
            "usageStatsUpdatedAt": Timestamp(date: Date())
        ], merge: true)

        try await DataManager().migrateLegacyUserDocumentIfNeeded(for: uid)
        let local = UsageSessionRecord(
            id: "future-session",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(180),
            appVersion: "1.21.1",
            lastPage: "home",
            pageDurations: [:],
            featureDurations: [:],
            featureViewCounts: [:],
            itemActionCounts: [:],
            newsTabDurations: [:],
            newsTabViewCounts: [:],
            notificationsEnabled: false,
            liveActivitiesEnabled: false,
            liveActivityActive: false
        )
        try await DataManager().appendUsageSessionToCloud(local, for: uid)

        let futureSnapshot = try await future.getDocument()
        let retained = try XCTUnwrap(futureSnapshot.data())
        XCTAssertEqual((retained["schemaVersion"] as? NSNumber)?.intValue, 7)
        XCTAssertEqual(retained["futureSentinel"] as? String, "must-survive")
        XCTAssertEqual(
            (retained["endedAt"] as? Timestamp)?.dateValue(),
            startedAt.addingTimeInterval(60)
        )
    }

    func testFarFuturePayloadTimestampCannotFreezeLiveScheduleOrEventUpdates() async throws {
        let initialClass = ClassItem(name: "Future-clock initial", teacher: "Old", room: "1")
        let updatedClass = ClassItem(name: "Normal-clock update", teacher: "New", room: "2")
        let initialEvent = CustomEvent(
            title: "Future-clock event",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        let updatedEvent = CustomEvent(
            title: "Normal-clock event update",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        let farFuture = Date().addingTimeInterval(10 * 365 * 24 * 60 * 60)
        try await seedCanonicalDocument(
            classes: [initialClass],
            events: [initialEvent],
            scheduleUpdatedAt: farFuture,
            eventsUpdatedAt: farFuture
        )

        let initialSchedule = expectation(description: "future schedule delivered")
        let updatedSchedule = expectation(description: "later schedule delivered")
        let initialEvents = expectation(description: "future events delivered")
        let updatedEvents = expectation(description: "later events delivered")
        let scheduleManager = DataManager()
        let scheduleObservation = scheduleManager.observeSchedule(for: uid) { result in
            guard case .success(let value) = result else { return }
            if value.0 == [initialClass] { initialSchedule.fulfill() }
            if value.0 == [updatedClass] { updatedSchedule.fulfill() }
        }
        let eventObservation = try XCTUnwrap(
            CloudEventsDataManager().observeEvents(for: uid) { result in
                guard case .success(let events) = result else { return }
                if events == [initialEvent] { initialEvents.fulfill() }
                if events == [updatedEvent] { updatedEvents.fulfill() }
            }
        )
        defer {
            scheduleObservation.cancel()
            eventObservation.cancel()
        }
        await fulfillment(of: [initialSchedule, initialEvents], timeout: 5)

        let normal = try encryptedMap(
            schemaVersion: 5,
            classes: [updatedClass],
            events: [updatedEvent],
            updatedAt: Date()
        )
        try await userDocument.setData(["cloudDataV5": normal], merge: true)
        await fulfillment(of: [updatedSchedule, updatedEvents], timeout: 5)
        withExtendedLifetime(scheduleManager) {}
    }

    func testFarFutureReleasedScheduleFailsClosedAcrossSaveListenerAndMigration() async throws {
        let canonicalClass = ClassItem(
            name: "Canonical schedule must survive",
            teacher: "Canonical",
            room: "C1"
        )
        let poisonedClass = ClassItem(
            name: "Clock-poisoned released schedule",
            teacher: "Legacy",
            room: "L1"
        )
        let localEdit = ClassItem(
            id: canonicalClass.id,
            name: "Local edit must not force a winner",
            teacher: "Local",
            room: "N1"
        )
        try await seedCanonicalDocument(classes: [canonicalClass])

        let manager = DataManager()
        let baseline = try await manager.loadFromCloud(for: uid)
        XCTAssertEqual(baseline.0, [canonicalClass])

        let farFuture = Date().addingTimeInterval(10 * 365 * 24 * 60 * 60)
        let released = try encryptedLegacyRoot(
            classes: [poisonedClass],
            events: [],
            lastUpdated: farFuture,
            includeEvents: false
        )
        try await userDocument.setData(released, merge: true)

        do {
            try await manager.saveToCloud(
                classes: [localEdit],
                theme: .defaultTheme,
                isSecondLunch: [false, false],
                for: uid
            )
            XCTFail("An active save must not arbitrate conflicting future-clock data.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: the transaction retained both source copies.
        }

        let listenerFailure = expectation(description: "future schedule listener fails closed")
        var fulfilledListenerFailure = false
        let observation = manager.observeSchedule(for: uid) { result in
            switch result {
            case .success(let schedule):
                XCTAssertNotEqual(schedule.0, [poisonedClass])
            case .failure:
                if !fulfilledListenerFailure {
                    fulfilledListenerFailure = true
                    listenerFailure.fulfill()
                }
            }
        }
        defer { observation.cancel() }
        await fulfillment(of: [listenerFailure], timeout: 5)

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("Migration must not let a far-future released schedule replace canonical data.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: no migration write was made.
        }

        let retained = try await documentData(userDocument)
        let retainedCloud = try XCTUnwrap(retained["cloudDataV5"] as? [String: Any])
        let retainedCanonical = try EncryptionService.shared.decrypt(
            try XCTUnwrap(retainedCloud["schedule"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        let retainedReleased = try EncryptionService.shared.decrypt(
            try XCTUnwrap(retained["classes"] as? String),
            as: [ClassItem].self,
            userId: uid
        )
        XCTAssertEqual(retainedCanonical, [canonicalClass])
        XCTAssertEqual(retainedReleased, [poisonedClass])
    }

    func testFarFutureReleasedEventsFailClosedAcrossSaveListenerAndMigration() async throws {
        let canonicalEvent = CustomEvent(
            title: "Canonical event must survive",
            startTime: Time(h: 8, m: 0, s: 0),
            endTime: Time(h: 9, m: 0, s: 0),
            applicableDays: ["G1"]
        )
        let poisonedEvent = CustomEvent(
            title: "Clock-poisoned released event",
            startTime: Time(h: 10, m: 0, s: 0),
            endTime: Time(h: 11, m: 0, s: 0),
            applicableDays: ["B1"]
        )
        let localEvent = CustomEvent(
            title: "Local event must not force a winner",
            startTime: Time(h: 12, m: 0, s: 0),
            endTime: Time(h: 13, m: 0, s: 0),
            applicableDays: ["G2"]
        )
        try await seedCanonicalDocument(events: [canonicalEvent])

        let manager = CloudEventsDataManager()
        let baseline = try await manager.loadEvents(for: uid)
        XCTAssertEqual(baseline, [canonicalEvent])

        let farFuture = Timestamp(
            date: Date().addingTimeInterval(10 * 365 * 24 * 60 * 60)
        )
        let releasedBlob = try EncryptionService.shared.encrypt(
            [poisonedEvent],
            userId: uid
        )
        try await userDocument.setData([
            "eventsEncrypted": true,
            "customEvents": releasedBlob,
            "eventsUpdatedAt": farFuture,
            "eventsLastUpdated": farFuture
        ], merge: true)

        do {
            try await manager.saveEvents([localEvent], for: uid)
            XCTFail("An active event save must not arbitrate conflicting future-clock data.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: the transaction retained both source copies.
        }

        let listenerFailure = expectation(description: "future event listener fails closed")
        var fulfilledListenerFailure = false
        let observation = try XCTUnwrap(
            manager.observeEvents(for: uid) { result in
                switch result {
                case .success(let events):
                    XCTAssertNotEqual(events, [poisonedEvent])
                case .failure:
                    if !fulfilledListenerFailure {
                        fulfilledListenerFailure = true
                        listenerFailure.fulfill()
                    }
                }
            }
        )
        defer { observation.cancel() }
        await fulfillment(of: [listenerFailure], timeout: 5)

        do {
            _ = try await CloudEventsDataManager().loadEvents(for: uid)
            XCTFail("Migration must not let far-future released events replace canonical data.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: no migration write was made.
        }

        let retained = try await documentData(userDocument)
        let retainedCloud = try XCTUnwrap(retained["cloudDataV5"] as? [String: Any])
        let retainedCanonical = try EncryptionService.shared.decrypt(
            try XCTUnwrap(retainedCloud["events"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        let retainedReleased = try EncryptionService.shared.decrypt(
            try XCTUnwrap(retained["customEvents"] as? String),
            as: [CustomEvent].self,
            userId: uid
        )
        XCTAssertEqual(retainedCanonical, [canonicalEvent])
        XCTAssertEqual(retainedReleased, [poisonedEvent])
    }

    func testFarFutureTransitionalSchema5CannotOutrankHealthyCanonicalData() async throws {
        let canonicalClass = ClassItem(name: "Canonical carrier", teacher: "C", room: "1")
        let transitionalClass = ClassItem(name: "Future carrier", teacher: "F", room: "2")
        let normalTime = Date(timeIntervalSince1970: 1_750_000_000)
        let farFuture = Date().addingTimeInterval(10 * 365 * 24 * 60 * 60)
        let canonical = try encryptedMap(
            schemaVersion: 5,
            classes: [canonicalClass],
            events: [],
            updatedAt: normalTime
        )
        let transitional = try encryptedMap(
            schemaVersion: 5,
            classes: [transitionalClass],
            events: [],
            updatedAt: farFuture
        )
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": canonical,
            "cloudData": transitional
        ])

        do {
            _ = try await DataManager().loadFromCloud(for: uid)
            XCTFail("An implausible carrier timestamp must not decide conflicting data.")
        } catch CloudDataSchemaError.corruptPayload {
            // Expected: both carriers remain untouched for recovery.
        }

        let retained = try await documentData(userDocument)
        XCTAssertEqual(
            (retained["cloudDataV5"] as? [String: Any])?["schedule"] as? String,
            canonical["schedule"] as? String
        )
        XCTAssertEqual(
            (retained["cloudData"] as? [String: Any])?["schedule"] as? String,
            transitional["schedule"] as? String
        )
    }

    private struct CombinedSchedulePayloadFixture: Codable {
        let classes: [ClassItem]
        let theme: ThemeColors
        let isSecondLunch: [Bool]
    }

    private var userDocument: DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    private var deletionRequestDocument: DocumentReference {
        Firestore.firestore().collection("accountDeletionRequests").document(uid)
    }

    private func documentData(_ reference: DocumentReference) async throws -> [String: Any] {
        let snapshot = try await reference.getDocument()
        return try XCTUnwrap(snapshot.data())
    }

    private func assertPermissionDenied(
        _ operationName: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Rules allowed \(operationName).", file: file, line: line)
        } catch {
            let firestoreError = error as NSError
            XCTAssertEqual(
                firestoreError.domain,
                FirestoreErrorDomain,
                "Unexpected error for \(operationName): \(error)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                firestoreError.code,
                7,
                "Expected permission-denied for \(operationName): \(error)",
                file: file,
                line: line
            )
        }
    }

    private func emulatorAdminDeleteDocument(_ reference: DocumentReference) async throws {
        _ = try await emulatorAdminRequest(method: "DELETE", reference: reference)
    }

    private func emulatorAdminDocumentFields(
        _ reference: DocumentReference
    ) async throws -> [String: Any] {
        let data = try await emulatorAdminRequest(method: "GET", reference: reference)
        let document = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(document["fields"] as? [String: Any])
    }

    private func emulatorAdminRequest(
        method: String,
        reference: DocumentReference
    ) async throws -> Data {
        let projectID = try XCTUnwrap(FirebaseApp.app()?.options.projectID)
        let encodedPath = reference.path
            .split(separator: "/")
            .map { segment in
                String(segment).addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed
                ) ?? String(segment)
            }
            .joined(separator: "/")
        let url = try XCTUnwrap(URL(string:
            "http://127.0.0.1:8080/v1/projects/\(projectID)/databases/(default)/documents/\(encodedPath)"
        ))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "FirebaseEmulatorAdminREST",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                ]
            )
        }
        return data
    }

    private func emulatorMapFields(_ value: Any?) -> [String: Any]? {
        guard
            let value = value as? [String: Any],
            let mapValue = value["mapValue"] as? [String: Any]
        else {
            return nil
        }
        return mapValue["fields"] as? [String: Any]
    }

    private func emulatorString(_ value: Any?) -> String? {
        (value as? [String: Any])?["stringValue"] as? String
    }

    private func emulatorInteger(_ value: Any?) -> Int? {
        guard let raw = (value as? [String: Any])?["integerValue"] else {
            return nil
        }
        if let raw = raw as? String {
            return Int(raw)
        }
        return (raw as? NSNumber)?.intValue
    }

    private func emulatorTimestamp(_ value: Any?) -> String? {
        (value as? [String: Any])?["timestampValue"] as? String
    }

    private var plaintextTheme: [String: Any] {
        [
            "primary": "#112233FF",
            "secondary": "#445566FF",
            "tertiary": "#FFFFFFFF"
        ]
    }

    private var corruptVersion5CloudData: [String: Any] {
        [
            "schemaVersion": 5,
            "schedule": "not-valid-base64-schedule",
            "theme": "not-valid-base64-theme",
            "isSecondLunch": "not-valid-base64-lunch",
            "events": "not-valid-base64-events",
            "scheduleUpdatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_800_000_000)),
            "eventsUpdatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_800_000_000))
        ]
    }

    private func canonicalSchemaVersion(in root: [String: Any]) -> Int? {
        let cloudData = root["cloudDataV5"] as? [String: Any]
        return (cloudData?["schemaVersion"] as? NSNumber)?.intValue
    }

    private func plaintextEvent(
        id: UUID,
        title: String,
        repeatPattern: String
    ) -> [String: Any] {
        [
            "id": id.uuidString,
            "title": title,
            "startTime": ["h": 8, "m": 0, "s": 0],
            "endTime": ["h": 9, "m": 0, "s": 0],
            "location": "Library",
            "note": "Legacy fixture",
            "color": "#FF0000",
            "repeatPattern": repeatPattern,
            "kind": CustomItemKind.event.rawValue,
            "applicableDays": ["G1"]
        ]
    }

    private func encryptedMap(
        schemaVersion: Int,
        classes: [ClassItem],
        events: [CustomEvent],
        updatedAt: Date
    ) throws -> [String: Any] {
        [
            "schemaVersion": schemaVersion,
            "schedule": try EncryptionService.shared.encrypt(classes, userId: uid),
            "theme": try EncryptionService.shared.encrypt(ThemeColors.defaultTheme, userId: uid),
            "isSecondLunch": try EncryptionService.shared.encrypt([false, false], userId: uid),
            "events": try EncryptionService.shared.encrypt(events, userId: uid),
            "scheduleUpdatedAt": Timestamp(date: updatedAt),
            "eventsUpdatedAt": Timestamp(date: updatedAt)
        ]
    }

    private func encryptedLegacyRoot(
        classes: [ClassItem],
        events: [CustomEvent],
        lastUpdated: Date,
        includeEvents: Bool = true
    ) throws -> [String: Any] {
        var root: [String: Any] = [
            "uid": uid,
            "encrypted": true,
            "classes": try EncryptionService.shared.encrypt(classes, userId: uid),
            "theme": try EncryptionService.shared.encrypt(ThemeColors.defaultTheme, userId: uid),
            "isSecondLunch": try EncryptionService.shared.encrypt([false, false], userId: uid),
            "lastUpdated": Timestamp(date: lastUpdated)
        ]
        if includeEvents {
            root["eventsEncrypted"] = true
            root["customEvents"] = try EncryptionService.shared.encrypt(events, userId: uid)
        }
        return root
    }

    private func establishedEventsContext(
        localEvents: [CustomEvent]
    ) throws -> (CustomEventsManager, AuthenticationManager) {
        let suiteName = "FirebaseEstablishedEvents.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let encoded = try JSONEncoder().encode(localEvents)
        defaults.set(encoded, forKey: "CustomEvents")
        defaults.set(encoded, forKey: "LocalCustomEvents.\(uid)")
        defaults.set("user:\(uid)", forKey: "LocalCustomEventsOwner")
        defaults.set(encoded, forKey: "LastSyncedCloudEvents.\(uid)")
        defaults.set(true, forKey: "EstablishedCloudEventsBaseline.\(uid)")

        let manager = CustomEventsManager(
            userDefaults: defaults,
            cloudSync: CloudEventsDataManager(),
            cloudLoadRetryDelays: [],
            cloudSaveDebounce: .seconds(30),
            cloudSaveRetryDelay: .seconds(30),
            connectivity: FirebaseEmulatorConnected()
        )
        let auth = AuthenticationManager(
            startAuthStateListener: false,
            userDefaults: defaults
        )
        auth.user = User(id: uid, email: "emulator@example.com")
        return (manager, auth)
    }

    private func seedCanonicalDocument(
        classes: [ClassItem] = [],
        events: [CustomEvent] = [],
        scheduleUpdatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        eventsUpdatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) async throws {
        var cloudData = try encryptedMap(
            schemaVersion: 5,
            classes: classes,
            events: events,
            updatedAt: scheduleUpdatedAt
        )
        cloudData["eventsUpdatedAt"] = Timestamp(date: eventsUpdatedAt)
        cloudData["migrationSentinel"] = "keep-cloud-data"
        try await userDocument.setData([
            "uid": uid,
            "cloudDataV5": cloudData
        ])
    }
}

private final class FirebaseEmulatorConnected: CloudConnectivityChecking {
    let isConnected = true
}
