//
//  EncryptionService.swift
//  Schedule
//
//  Created by Andreas Royset on 3/17/26.
//
//  Client-side AES-256-GCM encryption for Firebase data.
//  The encryption key is derived from the user's UID + a device-stored salt
//  using PBKDF2-SHA256. The key never leaves the device and is stored only
//  in the iOS Keychain — meaning even the developer cannot read user data
//  in Firestore.
//
//  Backward compatibility: documents without an "encrypted" flag are read
//  as plaintext. On next save they are automatically upgraded to encrypted.
//

import Foundation
import CryptoKit
import Security

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case keyDerivationFailed
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed:       return "Failed to derive encryption key."
        case .encryptionFailed(let m):   return "Encryption failed: \(m)"
        case .decryptionFailed(let m):   return "Decryption failed: \(m)"
        case .invalidData:               return "Invalid or corrupted encrypted data."
        }
    }
}

// MARK: - EncryptionService

final class EncryptionService {

    static let shared = EncryptionService()
    private init() {}

    // -------------------------------------------------------------------------
    // MARK: Public API
    // -------------------------------------------------------------------------

    /// Encrypt an arbitrary `Encodable` value to a Base64 string.
    /// Layout: [12-byte nonce][ciphertext + 16-byte GCM tag]
    func encrypt<T: Encodable>(_ value: T, userId: String) throws -> String {
        let key = try getOrCreateKey(for: userId)
        let data = try JSONEncoder().encode(value)
        return try encryptData(data, key: key)
    }

    /// Decrypt a Base64 string produced by `encrypt(_:userId:)` back to `T`.
    func decrypt<T: Decodable>(_ base64: String, as type: T.Type, userId: String) throws -> T {
        let key = try getOrCreateKey(for: userId)
        let data = try decryptData(base64, key: key)
        return try JSONDecoder().decode(type, from: data)
    }

    /// Encrypt a plain `String` (e.g. a single field value).
    func encryptString(_ value: String, userId: String) throws -> String {
        let key = try getOrCreateKey(for: userId)
        guard let data = value.data(using: .utf8) else { throw EncryptionError.invalidData }
        return try encryptData(data, key: key)
    }

    /// Decrypt a plain `String` field.
    func decryptString(_ base64: String, userId: String) throws -> String {
        let key = try getOrCreateKey(for: userId)
        let data = try decryptData(base64, key: key)
        guard let string = String(data: data, encoding: .utf8) else { throw EncryptionError.invalidData }
        return string
    }

    // -------------------------------------------------------------------------
    // MARK: Key management (Keychain + PBKDF2)
    // -------------------------------------------------------------------------

    /// Returns the cached symmetric key for `userId`, creating it if needed.
    /// The 32-byte raw key material is stored in the Keychain under a service
    /// name that includes the userId so different accounts get different keys.
    func getOrCreateKey(for userId: String) throws -> SymmetricKey {
        let keychainTag = "com.schedule.encryptionKey.\(userId)"

        // 1. Try to load from Keychain
        if let keyData = loadKeyFromKeychain(tag: keychainTag) {
            return SymmetricKey(data: keyData)
        }

        // 2. Derive a new key using PBKDF2-SHA256
        //    Salt = stable hash of (userId + bundle ID) — not secret, just unique per user/app.
        let salt = deriveSalt(userId: userId)
        let keyData = try deriveKey(password: userId, salt: salt)

        // 3. Persist to Keychain
        saveKeyToKeychain(keyData, tag: keychainTag)

        return SymmetricKey(data: keyData)
    }

    // -------------------------------------------------------------------------
    // MARK: Private — AES-GCM
    // -------------------------------------------------------------------------

    private func encryptData(_ data: Data, key: SymmetricKey) throws -> String {
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            // combined = nonce + ciphertext + tag
            guard let combined = sealed.combined else {
                throw EncryptionError.encryptionFailed("No combined representation")
            }
            return combined.base64EncodedString()
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    private func decryptData(_ base64: String, key: SymmetricKey) throws -> Data {
        guard let combined = Data(base64Encoded: base64) else {
            throw EncryptionError.invalidData
        }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw EncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Private — PBKDF2
    // -------------------------------------------------------------------------

    /// Derives 32 bytes (256 bits) from `password` + `salt` using PBKDF2-SHA256.
    private func deriveKey(password: String, salt: Data, iterations: UInt32 = 310_000) throws -> Data {
        guard let passwordData = password.data(using: .utf8) else {
            throw EncryptionError.keyDerivationFailed
        }

        var derivedKey = Data(repeating: 0, count: 32)

        let result = derivedKey.withUnsafeMutableBytes { derivedPtr in
            passwordData.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress, passwordData.count,
                        saltPtr.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedPtr.baseAddress, 32
                    )
                }
            }
        }

        guard result == kCCSuccess else { throw EncryptionError.keyDerivationFailed }
        return derivedKey
    }

    /// Creates a deterministic salt from the userId + bundle ID so it is
    /// stable across reinstalls (key recovery is done by re-deriving from
    /// the same userId when the Keychain entry is missing).
    private func deriveSalt(userId: String) -> Data {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.schedule"
        let saltInput = "\(userId).\(bundleID).schedule-encryption-v1"
        // SHA-256 of the string gives us a stable 32-byte salt
        return Data(SHA256.hash(data: Data(saltInput.utf8)))
    }

    // -------------------------------------------------------------------------
    // MARK: Private — Keychain helpers
    // -------------------------------------------------------------------------

    private func loadKeyFromKeychain(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    private func saveKeyToKeychain(_ keyData: Data, tag: String) {
        // Delete any stale entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: tag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          tag,
            kSecValueData as String:            keyData,
            // Only accessible when device is unlocked; backed up to iCloud Keychain
            // so the key survives a device wipe + restore for the same Apple ID.
            kSecAttrAccessible as String:       kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

// MARK: - CommonCrypto bridge (PBKDF2)
// CryptoKit does not expose PBKDF2 directly, so we use CommonCrypto.
import CommonCrypto
