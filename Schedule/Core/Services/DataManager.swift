//
//  DataManager.swift
//  Schedule
//
//  Encrypts all user data before writing to Firestore.
//  Old documents (no "encrypted" flag) are read as plain text and
//  upgraded to encrypted format on the next save — backward compatible.
//

import FirebaseFirestore

@MainActor
class DataManager: ObservableObject {
    private let db = Firestore.firestore()
    private let encryption = EncryptionService.shared

    // -------------------------------------------------------------------------
    // MARK: Save
    // -------------------------------------------------------------------------

    func saveToCloud(
        classes: [ClassItem],
        theme: ThemeColors,
        isSecondLunch: [Bool],
        for userId: String
    ) async throws {
        let encryptedClasses  = try encryption.encrypt(classes,       userId: userId)
        let encryptedTheme    = try encryption.encrypt(theme,         userId: userId)
        let encryptedLunch    = try encryption.encrypt(isSecondLunch, userId: userId)

        try await db.collection("users").document(userId).setData([
            "encrypted":     true,
            "classes":       encryptedClasses,
            "theme":         encryptedTheme,
            "isSecondLunch": encryptedLunch,
            "lastUpdated":   Timestamp()
        ], merge: true)
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
            return try loadEncrypted(data, userId: userId)
        }

        return loadPlaintext(data)
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

    func touchLastUpdated(for userId: String) async throws {
        try await db.collection("users").document(userId).setData([
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func appendUsageSessionToCloud(_ session: UsageSessionRecord, for userId: String) async throws {
        let sessionData: [String: Any] = [
            "startedAt": Timestamp(date: session.startedAt),
            "endedAt": Timestamp(date: session.endedAt)
        ]

        try await db.collection("users").document(userId).setData([
            "usageStats.sessions": FieldValue.arrayUnion([sessionData]),
            "usageStatsUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func clearUsageStats(for userId: String) async throws {
        try await db.collection("users").document(userId).setData([
            "usageStats": [
                "sessions": []
            ],
            "usageStatsUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // -------------------------------------------------------------------------
    // MARK: Other operations
    // -------------------------------------------------------------------------

    func deleteUserData(for userId: String) async throws {
        try await db.collection("users").document(userId).delete()
    }

    // -------------------------------------------------------------------------
    // MARK: Private helpers
    // -------------------------------------------------------------------------

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
            ClassItem(
                name:    dict["name"]    ?? "",
                teacher: dict["teacher"] ?? "",
                room:    dict["room"]    ?? ""
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
