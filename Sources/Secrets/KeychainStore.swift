import DaybriefCore
import Foundation
import os
import Security

/// Serialized, type-safe access to Daybrief's secrets in the macOS keychain.
///
/// Every secret — per-account OAuth access+refresh tokens, the BYO Google client
/// id/secret, the Slack user token, the LLM API key, and the SQLCipher database
/// key — is a `kSecClassGenericPassword` item in the **data-protection keychain**,
/// keyed by a ``SecretRef`` (`service` + `account`). Writes upsert (add, falling
/// back to update on `errSecDuplicateItem`); the actor serializes Daybrief's own
/// add/update races (e.g. two connectors refreshing tokens at once) on top of the
/// already-thread-safe `SecItem*` C API.
///
/// ### Keychain selection and the entitlement caveat (design §10)
/// All calls set `kSecUseDataProtectionKeychain` and use the accessibility class
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — see ``KeychainQuery`` for
/// why. The data-protection keychain on an *unsandboxed* Developer-ID app is
/// reached via the implicit `application-identifier` access group; no
/// `keychain-access-groups` entitlement is set (adding an unnecessary one is a
/// common cause of `errSecMissingEntitlement`). This is the M0 open question
/// (§10, §20.1): if that posture proves unworkable on the notarized build, the
/// documented fallback is the legacy file-based login keychain, reached by
/// dropping `kSecUseDataProtectionKeychain` from ``KeychainQuery``. That fallback
/// is intentionally not wired until verified empirically.
///
/// ### Logging
/// `service`/`account` are non-secret coordinates and may be logged; secret
/// **values** are never interpolated, and any incidental secret-adjacent material
/// is logged with `privacy: .private`. Nothing here lets secret bytes reach
/// `os_log`.
public actor KeychainStore {
    private let logger = Logger(subsystem: "co.daybrief.secrets", category: "KeychainStore")

    /// Creates a keychain store. Stateless beyond the actor's serialization.
    public init() {}

    // MARK: - Data CRUD

    /// Stores raw bytes for `ref`, creating the item or overwriting an existing one.
    ///
    /// Implemented as an upsert: `SecItemAdd` first, and on `errSecDuplicateItem`
    /// a `SecItemUpdate` of the value. The accessibility class is fixed on the add
    /// path only (it cannot be reliably changed by update).
    public func setData(_ data: Data, for ref: SecretRef) throws {
        let addStatus = SecItemAdd(KeychainQuery.add(ref, data: data) as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            logger.debug("stored secret \(ref.service, privacy: .public)/\(ref.account, privacy: .public)")
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                KeychainQuery.base(for: ref) as CFDictionary,
                KeychainQuery.updateAttributes(data: data) as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                logger.error("update failed for \(ref.service, privacy: .public)/\(ref.account, privacy: .public): \(updateStatus)")
                throw SecretsError.from(updateStatus)
            }
            logger.debug("updated secret \(ref.service, privacy: .public)/\(ref.account, privacy: .public)")
        default:
            logger.error("add failed for \(ref.service, privacy: .public)/\(ref.account, privacy: .public): \(addStatus)")
            throw SecretsError.from(addStatus)
        }
    }

    /// Returns the raw bytes stored for `ref`, or `nil` if no such item exists.
    ///
    /// Throws ``SecretsError/interactionNotAllowed`` if the keychain is locked
    /// (e.g. before the first post-boot unlock) — callers running after wake should
    /// treat that as transient and retry once the machine is unlocked.
    public func getData(for ref: SecretRef) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(KeychainQuery.copy(ref) as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecretsError.malformedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            logger.error("read failed for \(ref.service, privacy: .public)/\(ref.account, privacy: .public): \(status)")
            throw SecretsError.from(status)
        }
    }

    /// Deletes the item for `ref`. Deleting a non-existent item is a no-op (not an error).
    public func delete(_ ref: SecretRef) throws {
        let status = SecItemDelete(KeychainQuery.base(for: ref) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            logger.debug("deleted secret \(ref.service, privacy: .public)/\(ref.account, privacy: .public)")
        default:
            logger.error("delete failed for \(ref.service, privacy: .public)/\(ref.account, privacy: .public): \(status)")
            throw SecretsError.from(status)
        }
    }

    // MARK: - String convenience

    /// Stores a string for `ref` (UTF-8 encoded).
    public func setString(_ string: String, for ref: SecretRef) throws {
        try setData(Data(string.utf8), for: ref)
    }

    /// Returns the string stored for `ref`, or `nil` if no such item exists.
    ///
    /// Throws ``SecretsError/malformedData`` if the stored bytes are not valid UTF-8.
    public func getString(for ref: SecretRef) throws -> String? {
        guard let data = try getData(for: ref) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw SecretsError.malformedData
        }
        return string
    }

    // MARK: - Codable convenience

    /// Stores a `Codable` value for `ref` as JSON.
    ///
    /// The intended unit is one blob per secret — e.g. an `OAuthToken` carrying
    /// access token, refresh token, and expiry together — so a refresh overwrites
    /// them atomically rather than leaving the three fields out of sync across
    /// separate items.
    public func setCodable<T: Codable & Sendable>(_ value: T, for ref: SecretRef) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            // An encode failure is a programming error, not a keychain one, but we
            // never leak the (potentially secret) value into the thrown error.
            throw SecretsError.malformedData
        }
        try setData(data, for: ref)
    }

    /// Returns the `Codable` value stored for `ref`, or `nil` if no such item exists.
    ///
    /// Throws ``SecretsError/malformedData`` if the stored bytes cannot be decoded as `T`.
    public func getCodable<T: Codable & Sendable>(_: T.Type, for ref: SecretRef) throws -> T? {
        guard let data = try getData(for: ref) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SecretsError.malformedData
        }
    }

    // MARK: - Database key

    /// Returns the 256-bit SQLCipher database key, generating and persisting one on first call.
    ///
    /// Stored under ``SecretRef/databaseKey``. On first launch 32 random bytes are
    /// drawn via `SecRandomCopyBytes` and written to the keychain; every later call
    /// returns the same bytes. `Persistence` applies these as a SQLCipher *raw* key
    /// (`PRAGMA key = "x'<64-hex>'"`, skipping KDF) and must read them lazily at DB
    /// open time — the key is never persisted anywhere but the keychain.
    public func databaseKey() throws -> Data {
        if let existing = try getData(for: .databaseKey) {
            return existing
        }
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            // `count == 32` makes baseAddress non-nil; force-unwrap is provably safe.
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            logger.error("database key generation failed: \(status)")
            throw SecretsError.randomGenerationFailed(status)
        }
        try setData(bytes, for: .databaseKey)
        logger.debug("generated and stored a new database key")
        return bytes
    }
}
