import DaybriefCore
import Foundation
@testable import Secrets
import Security
import Testing

/// Live tests that exercise the real macOS keychain.
///
/// The keychain may be unavailable in CI (no login keychain / no signing identity),
/// so each test first checks ``keychainIsAvailable`` and returns early when it is
/// not, rather than failing the suite. Run them on a developer machine for real
/// coverage. Every test uses a per-run unique service prefix and cleans up after
/// itself so repeated runs never collide and nothing leaks into Keychain Access.
@Suite("KeychainStore (live)")
struct KeychainStoreTests {
    /// A probe ref under a unique service so it can never clash with real items.
    private static func probeRef() -> SecretRef {
        SecretRef(service: "co.daybrief.test.\(UUID().uuidString)", account: "probe")
    }

    /// Whether the data-protection keychain accepts a round-trip add/delete here.
    ///
    /// Returns `false` in environments where the keychain is inaccessible (common
    /// in CI), letting live tests skip gracefully.
    private func keychainIsAvailable() -> Bool {
        let ref = Self.probeRef()
        let addStatus = SecItemAdd(KeychainQuery.add(ref, data: Data([0x00])) as CFDictionary, nil)
        if addStatus == errSecSuccess {
            SecItemDelete(KeychainQuery.base(for: ref) as CFDictionary)
            return true
        }
        return false
    }

    /// A fresh, unique ref for a single test; the caller deletes it when done.
    private func makeRef(_ account: String = "default") -> SecretRef {
        SecretRef(service: "co.daybrief.test.\(UUID().uuidString)", account: account)
    }

    @Test("set then get round-trips raw data")
    func dataRoundTrips() async throws {
        guard keychainIsAvailable() else { return }
        let store = KeychainStore()
        let ref = makeRef()
        defer { try? deleteSync(ref) }

        let payload = Data([0x01, 0x02, 0x03, 0xFF])
        try await store.setData(payload, for: ref)
        let read = try await store.getData(for: ref)
        #expect(read == payload)
    }

    @Test("get returns nil for a missing item")
    func getMissingReturnsNil() async throws {
        guard keychainIsAvailable() else { return }
        let store = KeychainStore()
        let read = try await store.getData(for: makeRef("never-stored"))
        #expect(read == nil)
    }

    @Test("setData upserts — a second write overwrites rather than throwing")
    func setUpserts() async throws {
        guard keychainIsAvailable() else { return }
        let store = KeychainStore()
        let ref = makeRef()
        defer { try? deleteSync(ref) }

        try await store.setData(Data([0xAA]), for: ref)
        try await store.setData(Data([0xBB, 0xCC]), for: ref) // must not throw errSecDuplicateItem
        let read = try await store.getData(for: ref)
        #expect(read == Data([0xBB, 0xCC]))
    }

    @Test("delete removes the item; deleting again is a no-op")
    func deleteRemovesAndIsIdempotent() async throws {
        guard keychainIsAvailable() else { return }
        let store = KeychainStore()
        let ref = makeRef()

        try await store.setData(Data([0x09]), for: ref)
        try await store.delete(ref)
        #expect(try await store.getData(for: ref) == nil)
        try await store.delete(ref) // deleting a non-existent item does not throw
    }

    @Test("string convenience round-trips UTF-8")
    func stringRoundTrips() async throws {
        guard keychainIsAvailable() else { return }
        let store = KeychainStore()
        let ref = makeRef()
        defer { try? deleteSync(ref) }

        try await store.setString("xoxp-secret-token-éµ", for: ref)
        #expect(try await store.getString(for: ref) == "xoxp-secret-token-éµ")
    }

    @Test("codable convenience round-trips a token-shaped blob atomically")
    func codableRoundTrips() async throws {
        guard keychainIsAvailable() else { return }
        let store = KeychainStore()
        let ref = makeRef()
        defer { try? deleteSync(ref) }

        let token = TestToken(accessToken: "ya29.abc", refreshToken: "1//xyz", expiresAt: 1_750_000_000)
        try await store.setCodable(token, for: ref)
        let restored = try await store.getCodable(TestToken.self, for: ref)
        #expect(restored == token)
    }

    @Test("databaseKey generates a stable 256-bit key and returns it on later calls")
    func databaseKeyIsStable256Bit() async throws {
        guard keychainIsAvailable() else { return }
        // The DB key lives at a well-known ref shared across the app; clean up so a
        // dev machine doesn't accumulate a test-written key. (Harmless either way —
        // a real first launch regenerates it.)
        let store = KeychainStore()
        defer { try? deleteSync(.databaseKey) }
        try? deleteSync(.databaseKey)

        let first = try await store.databaseKey()
        #expect(first.count == 32)
        let second = try await store.databaseKey()
        #expect(second == first) // stable across calls
    }

    // MARK: - Helpers

    private struct TestToken: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
    }

    /// Synchronous delete used by `defer` cleanup (defer can't `await`).
    private func deleteSync(_ ref: SecretRef) throws {
        let status = SecItemDelete(KeychainQuery.base(for: ref) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretsError.from(status)
        }
    }
}
