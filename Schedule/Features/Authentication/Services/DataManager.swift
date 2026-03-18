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

        // --- Encrypt each sensitive payload ---
        let encryptedClasses = try encryption.encrypt(classes,      userId: userId)
        let encryptedTheme   = try encryption.encrypt(theme,        userId: userId)
        let encryptedLunch   = try encryption.encrypt(isSecondLunch, userId: userId)

        try await db.collection("users").document(userId).setData([
            "encrypted":        true,           // ← migration flag
            "classes":          encryptedClasses,
            "theme":            encryptedTheme,
            "isSecondLunch":    encryptedLunch,
            "lastUpdated":      Timestamp()
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

        // ── Encrypted path (new format) ──────────────────────────────────────
        if data["encrypted"] as? Bool == true {
            return try loadEncrypted(data, userId: userId)
        }

        // ── Legacy plaintext path (old format) ──────────────────────────────
        // Still works; will be upgraded automatically on next save.
        return loadPlaintext(data)
    }

    // -------------------------------------------------------------------------
    // MARK: Other operations (unchanged)
    // -------------------------------------------------------------------------

    func deleteUserData(for userId: String) async throws {
        try await db.collection("users").document(userId).delete()
    }

    func recordPolicyAcceptance(for userId: String, version: String) async throws {
        try await db.collection("users").document(userId).setData([
            "privacyPolicy": [
                "accepted":  true,
                "version":   version,
                "timestamp": FieldValue.serverTimestamp()
            ]
        ], merge: true)
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

        // classes
        var classes: [ClassItem] = []
        if let blob = data["classes"] as? String {
            classes = (try? encryption.decrypt(blob, as: [ClassItem].self, userId: userId)) ?? []
        }

        // theme
        var theme = defaultTheme
        if let blob = data["theme"] as? String {
            theme = (try? encryption.decrypt(blob, as: ThemeColors.self, userId: userId)) ?? defaultTheme
        }

        // isSecondLunch
        var isSecondLunch = [false, false]
        if let blob = data["isSecondLunch"] as? String {
            isSecondLunch = (try? encryption.decrypt(blob, as: [Bool].self, userId: userId)) ?? [false, false]
        }

        return (classes, theme, isSecondLunch)
    }

    /// Reads the old un-encrypted Firestore structure (pre-encryption).
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
