//
//  DataManager.swift
//  Schedule
//
//  Encrypts all user data before writing to Firestore.
//  Old documents (no "encrypted" flag) are read as plain text and
//  upgraded to encrypted format on the next save — backward compatible.
//

import FirebaseFirestore
import Foundation

@MainActor
class DataManager: ObservableObject {
    private let db = Firestore.firestore()
    private let encryption = EncryptionService.shared

    private struct CloudSnapshot: Equatable {
        let classes: [ClassItem]
        let theme: ThemeColors
        let isSecondLunch: [Bool]
        let isEncrypted: Bool
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

    // Shared across DataManager instances so saves made from different screens
    // still benefit from the snapshot populated by the initial cloud load.
    private static var snapshots: [String: CloudSnapshot] = [:]
    private static var fieldsNeedingRewrite: [String: Set<CloudField>] = [:]
    private static var pendingSaves: [String: PendingSave] = [:]

    // -------------------------------------------------------------------------
    // MARK: Save
    // -------------------------------------------------------------------------

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
            try await writeChangedScheduleFields(
                classes: classes,
                theme: theme,
                isSecondLunch: isSecondLunch,
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

    // -------------------------------------------------------------------------
    // MARK: Load  (supports both encrypted and legacy plaintext documents)
    // -------------------------------------------------------------------------

    func loadFromCloud(for userId: String) async throws -> ([ClassItem], ThemeColors, [Bool]) {
        let doc  = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data() else {
            return ([], defaultTheme, [false, false])
        }

        if data["encrypted"] as? Bool == true {
            let loaded = try loadEncrypted(data, userId: userId)
            Self.snapshots[userId] = CloudSnapshot(
                classes: loaded.0,
                theme: loaded.1,
                isSecondLunch: loaded.2,
                isEncrypted: true
            )
            if loaded.0.contains(where: \.needsIDMigration) {
                Self.fieldsNeedingRewrite[userId, default: []].insert(.classes)
            }
            return loaded
        }

        let loaded = loadPlaintext(data)
        Self.snapshots[userId] = CloudSnapshot(
            classes: loaded.0,
            theme: loaded.1,
            isSecondLunch: loaded.2,
            isEncrypted: false
        )
        // Flipping the encryption marker without rewriting these values would
        // make legacy plaintext unreadable, so migrate each payload once.
        Self.fieldsNeedingRewrite[userId] = [.classes, .theme, .isSecondLunch]
        return loaded
    }

    // -------------------------------------------------------------------------
    // MARK: Policy
    // -------------------------------------------------------------------------

    func recordPolicyAcceptance(for userId: String, version: String) async throws {
        try await db.collection("users").document(userId).setData([
            "privacyPolicy": [
                "accepted":  true,
                "version":   version,
                "timestamp": FieldValue.serverTimestamp()
            ]
        ], merge: true)
    }

    /// Returns `true` if the user has never accepted the policy
    /// OR if their stored version is older than `currentVersion`.
    func checkPolicyNeedsRenewal(for userId: String, currentVersion: String) async throws -> Bool {
        let doc = try await db.collection("users").document(userId).getDocument()

        guard let data = doc.data() else {
            // No document at all — treat as needing acceptance
            return true
        }

        guard
            let policyDict = data["privacyPolicy"] as? [String: Any],
            let accepted   = policyDict["accepted"] as? Bool, accepted,
            let stored     = policyDict["version"]  as? String
        else {
            // Missing or malformed policy record
            return true
        }

        // Simple string comparison works because versions are ISO dates (YYYY-MM-DD)
        return stored < currentVersion
    }

    func appendUsageSessionToCloud(_ session: UsageSessionRecord, for userId: String) async throws {
        let sessionData: [String: Any] = [
            "schemaVersion": 2,
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

        let userRef = db.collection("users").document(userId)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let doc = try transaction.getDocument(userRef)
                let data = doc.data()
                let nestedUsageStats = data?["usageStats"] as? [String: Any]
                let nestedSessions = nestedUsageStats?["sessions"] as? [[String: Any]] ?? []
                let legacySessions = data?["usageStats.sessions"] as? [[String: Any]] ?? []
                let hasLegacySessionsField = data?["usageStats.sessions"] != nil

                guard doc.exists else {
                    transaction.setData([
                        "usageStats": ["sessions": [sessionData]],
                        "usageStatsUpdatedAt": FieldValue.serverTimestamp()
                    ], forDocument: userRef, merge: true)
                    return nil
                }

                let existingSession = nestedSessions.first { $0["id"] as? String == session.id }
                let isNewerReplacement = existingSession.map {
                    Self.usageSessionEndedAt($0) < session.endedAt
                } ?? false
                let needsSchemaMigration = nestedSessions.contains {
                    ($0["schemaVersion"] as? NSNumber)?.intValue != 2
                }

                if hasLegacySessionsField || needsSchemaMigration || isNewerReplacement {
                    let sessions = Self.normalizedUsageSessions(
                        nestedSessions + legacySessions + [sessionData]
                    )
                    transaction.updateData([
                        FieldPath(["usageStats", "sessions"]): sessions,
                        FieldPath(["usageStats.sessions"]): FieldValue.delete(),
                        "usageStatsUpdatedAt": FieldValue.serverTimestamp()
                    ] as [AnyHashable: Any], forDocument: userRef)
                } else if existingSession == nil {
                    transaction.updateData([
                        FieldPath(["usageStats", "sessions"]): FieldValue.arrayUnion([sessionData]),
                        "usageStatsUpdatedAt": FieldValue.serverTimestamp()
                    ] as [AnyHashable: Any], forDocument: userRef)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    func clearUsageStats(for userId: String) async throws {
        let userRef = db.collection("users").document(userId)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let doc = try transaction.getDocument(userRef)
                if doc.exists {
                    transaction.updateData([
                        FieldPath(["usageStats", "sessions"]): [],
                        FieldPath(["usageStats.sessions"]): FieldValue.delete(),
                        "usageStatsUpdatedAt": FieldValue.serverTimestamp()
                    ] as [AnyHashable: Any], forDocument: userRef)
                } else {
                    transaction.setData([
                        "usageStats": ["sessions": []],
                        "usageStatsUpdatedAt": FieldValue.serverTimestamp()
                    ], forDocument: userRef, merge: true)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Other operations
    // -------------------------------------------------------------------------

    func deleteUserData(for userId: String) async throws {
        try await db.collection("users").document(userId).delete()
        Self.snapshots[userId] = nil
        Self.fieldsNeedingRewrite[userId] = nil
    }

    // -------------------------------------------------------------------------
    // MARK: Private helpers
    // -------------------------------------------------------------------------

    nonisolated private static func normalizedUsageSessions(
        _ sessions: [[String: Any]]
    ) -> [[String: Any]] {
        var normalized: [[String: Any]] = []

        for session in sessions.map(Self.normalizedUsageSession) {
            guard let id = session["id"] as? String,
                  let index = normalized.firstIndex(where: { $0["id"] as? String == id }) else {
                normalized.append(session)
                continue
            }

            if Self.usageSessionEndedAt(normalized[index]) < Self.usageSessionEndedAt(session) {
                normalized[index] = session
            }
        }

        return normalized
    }

    nonisolated private static func normalizedUsageSession(
        _ session: [String: Any]
    ) -> [String: Any] {
        var normalized = session
        normalized["schemaVersion"] = 2
        normalized.removeValue(forKey: "duration")
        normalized.removeValue(forKey: "itemBreakdown")

        if normalized["featureViewCounts"] == nil,
           let legacyCounts = normalized["featureCounts"] {
            normalized["featureViewCounts"] = legacyCounts
        }
        normalized.removeValue(forKey: "featureCounts")

        if let legacyTabs = normalized["newsTabBreakdown"] as? [String: Any] {
            if normalized["newsTabDurations"] == nil {
                normalized["newsTabDurations"] = legacyTabs.mapValues { value in
                    (value as? [String: Any])?["duration"] ?? 0
                }
            }
            if normalized["newsTabViewCounts"] == nil {
                normalized["newsTabViewCounts"] = legacyTabs.mapValues { value in
                    (value as? [String: Any])?["viewCount"] ?? 0
                }
            }
        }
        normalized.removeValue(forKey: "newsTabBreakdown")

        return normalized
    }

    nonisolated private static func usageSessionEndedAt(_ session: [String: Any]) -> Date {
        if let timestamp = session["endedAt"] as? Timestamp {
            return timestamp.dateValue()
        }
        return session["endedAt"] as? Date ?? .distantPast
    }

    private func writeChangedScheduleFields(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        for userId: String
    ) async throws {
        let nextSnapshot = CloudSnapshot(
            classes: classes,
            theme: theme,
            isSecondLunch: isSecondLunch,
            isEncrypted: true
        )
        let previous = Self.snapshots[userId]
        let rewrites = Self.fieldsNeedingRewrite[userId] ?? []
        var changedData: [String: Any] = [:]

        if previous?.classes != classes || rewrites.contains(.classes) {
            changedData["classes"] = try encryption.encrypt(classes, userId: userId)
        }
        if previous?.theme != theme || rewrites.contains(.theme) {
            changedData["theme"] = try encryption.encrypt(theme, userId: userId)
        }
        if previous?.isSecondLunch != isSecondLunch || rewrites.contains(.isSecondLunch) {
            changedData["isSecondLunch"] = try encryption.encrypt(isSecondLunch, userId: userId)
        }
        if previous?.isEncrypted != true {
            changedData["encrypted"] = true
        }

        guard !changedData.isEmpty else { return }

        changedData["lastUpdated"] = FieldValue.serverTimestamp()
        try await db.collection("users").document(userId).setData(changedData, merge: true)
        Self.snapshots[userId] = nextSnapshot
        Self.fieldsNeedingRewrite[userId] = nil
    }

    private func clearPendingSave(_ saveID: UUID, for userId: String) {
        guard Self.pendingSaves[userId]?.id == saveID else { return }
        Self.pendingSaves[userId] = nil
    }

    private var defaultTheme: ThemeColors {
        ThemeColors(primary: "#00A5FFFF", secondary: "#00A5FF19", tertiary: "#FFFFFFFF")
    }

    private func loadEncrypted(
        _ data: [String: Any],
        userId: String
    ) throws -> ([ClassItem], ThemeColors, [Bool]) {

        var classes: [ClassItem] = []
        if let blob = data["classes"] as? String {
            classes = (try? encryption.decrypt(blob, as: [ClassItem].self, userId: userId)) ?? []
        }

        var theme = defaultTheme
        if let blob = data["theme"] as? String {
            theme = (try? encryption.decrypt(blob, as: ThemeColors.self, userId: userId)) ?? defaultTheme
        }

        var isSecondLunch = [false, false]
        if let blob = data["isSecondLunch"] as? String {
            isSecondLunch = (try? encryption.decrypt(blob, as: [Bool].self, userId: userId)) ?? [false, false]
        }

        return (classes, theme, isSecondLunch)
    }

    private func loadPlaintext(_ data: [String: Any]) -> ([ClassItem], ThemeColors, [Bool]) {
        let classesArray = (data["classes"] as? [[String: String]]) ?? []
        let classes = classesArray.map { dict in
            let persistedID = dict["id"].flatMap(UUID.init(uuidString:))
            return ClassItem(
                id: persistedID ?? UUID(),
                name:    dict["name"]    ?? "",
                teacher: dict["teacher"] ?? "",
                room:    dict["room"]    ?? "",
                needsIDMigration: persistedID == nil
            )
        }

        let themeDict = (data["theme"] as? [String: String]) ?? [:]
        let theme = ThemeColors(
            primary:   themeDict["primary"]   ?? "#00A5FFFF",
            secondary: themeDict["secondary"] ?? "#00A5FF19",
            tertiary:  themeDict["tertiary"]  ?? "#FFFFFFFF"
        )

        let isSecondLunch = (data["isSecondLunch"] as? [Bool]) ?? [false, false]
        return (classes, theme, isSecondLunch)
    }
}
