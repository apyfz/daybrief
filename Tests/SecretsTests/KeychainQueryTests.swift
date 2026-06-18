import DaybriefCore
import Foundation
@testable import Secrets
import Security
import Testing

/// Pure tests of the query-dictionary builder — no live keychain, always run.
@Suite("KeychainQuery")
struct KeychainQueryTests {
    private let ref = SecretRef(service: "co.daybrief.test.service", account: "alice@example.com")

    @Test("every query targets the login keychain (no data-protection flag)")
    func everyQueryUsesLoginKeychain() {
        // Daybrief is unsandboxed Developer-ID, so it uses the file-based login
        // keychain: the data-protection flag must be ABSENT (setting it fails with
        // errSecMissingEntitlement on a build without a keychain access group).
        let queries: [[CFString: Any]] = [
            KeychainQuery.base(for: ref),
            KeychainQuery.add(ref, data: Data([0x01])),
            KeychainQuery.copy(ref),
        ]
        for query in queries {
            #expect(query[kSecUseDataProtectionKeychain] == nil)
        }
    }

    @Test("base query is the generic-password primary key, pinned non-synchronizable")
    func baseIsTheGenericPasswordPrimaryKey() {
        let query = KeychainQuery.base(for: ref)
        #expect(query[kSecClass] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService] as? String == ref.service)
        #expect(query[kSecAttrAccount] as? String == ref.account)
        #expect(query[kSecAttrSynchronizable] as? Bool == false)
        // No access group is set — the unsandboxed app uses its implicit group (design §10).
        #expect(query[kSecAttrAccessGroup] == nil)
        // The base (used for delete/update/copy seeds) carries no value or accessibility.
        #expect(query[kSecValueData] == nil)
        #expect(query[kSecAttrAccessible] == nil)
    }

    @Test("add query carries the value (login keychain: no accessibility attribute)")
    func addQueryCarriesValue() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let query = KeychainQuery.add(ref, data: data)
        #expect(query[kSecValueData] as? Data == data)
        // The login keychain doesn't honor kSecAttrAccessible — it must be absent.
        #expect(query[kSecAttrAccessible] == nil)
        // Add still includes the full primary key.
        #expect(query[kSecAttrService] as? String == ref.service)
        #expect(query[kSecAttrAccount] as? String == ref.account)
    }

    @Test("copy query requests exactly one item's data")
    func copyQueryRequestsOneItemData() {
        let query = KeychainQuery.copy(ref)
        #expect(query[kSecReturnData] as? Bool == true)
        #expect(query[kSecMatchLimit] as? String == kSecMatchLimitOne as String)
        // Copy must not carry a value or set accessibility.
        #expect(query[kSecValueData] == nil)
        #expect(query[kSecAttrAccessible] == nil)
    }

    @Test("update attributes change only the value, never the accessibility class")
    func updateAttributesChangeOnlyValue() {
        let data = Data([0x42])
        let attributes = KeychainQuery.updateAttributes(data: data)
        #expect(attributes[kSecValueData] as? Data == data)
        #expect(attributes[kSecAttrAccessible] == nil)
        #expect(attributes[kSecClass] == nil)
    }

    @Test("distinct refs produce distinct account/service coordinates")
    func distinctRefsAreDistinct() {
        let a = KeychainQuery.base(for: SecretRef(service: "svc", account: "a"))
        let b = KeychainQuery.base(for: SecretRef(service: "svc", account: "b"))
        #expect(a[kSecAttrAccount] as? String != b[kSecAttrAccount] as? String)
        #expect(a[kSecAttrService] as? String == b[kSecAttrService] as? String)
    }
}
