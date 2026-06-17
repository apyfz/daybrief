import DaybriefCore
import Foundation
import Security

/// Pure builder for the `SecItem*` query dictionaries used by ``KeychainStore``.
///
/// Factored out of the actor so the dictionary shape — which keys are present,
/// which keychain is targeted, the accessibility class — can be unit-tested
/// without ever touching the real keychain (the live `SecItem*` calls require a
/// keychain that may be unavailable in CI).
///
/// All Daybrief secrets are `kSecClassGenericPassword` items in the macOS
/// **data-protection keychain**. Every query therefore sets
/// `kSecUseDataProtectionKeychain`: omitting it on macOS silently routes the call
/// to the legacy file-based keychain, which has different uniqueness/attribute
/// semantics and does not honor `kSecAttrAccessible` the same way — mixing the
/// two produces phantom `errSecItemNotFound`. We also pin
/// `kSecAttrSynchronizable` to `false` so items never reach iCloud Keychain
/// (local-first / private-by-default) and so the generic-password primary key
/// `(class, service, account, accessGroup, synchronizable)` stays deterministic.
enum KeychainQuery {
    /// Accessibility class for every Daybrief item.
    ///
    /// `AfterFirstUnlockThisDeviceOnly` keeps secrets readable after the first
    /// post-boot login for the rest of the session — including while the screen
    /// is locked — so a post-wake scheduled brief can read its tokens. A
    /// `WhenUnlocked`-class item would fail with `errSecInteractionNotAllowed`
    /// whenever the screen is locked, breaking that core feature. `ThisDeviceOnly`
    /// keeps the bytes off iCloud Keychain and out of device migration/backup.
    ///
    /// Note: `kSecAttrAccessible` cannot be reliably changed by `SecItemUpdate`;
    /// to migrate an item's accessibility class you must delete and re-add it.
    /// Hence the class is set on the **add** path only (see ``add(_:data:)``).
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is an immutable, process-wide
    /// system constant (a `CFString` lacking `Sendable` conformance). It is read-only and
    /// never mutated, so concurrent reads are safe — hence `nonisolated(unsafe)`.
    nonisolated(unsafe) static let accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// The base primary-key query identifying exactly one generic-password item.
    ///
    /// Used as-is for delete/update and as the seed for add/copy queries.
    ///
    /// > Entitlement caveat (design §10, unresolved in M0): on an *unsandboxed*
    /// > Developer-ID app the data-protection keychain is reached via the app's
    /// > implicit `application-identifier` access group — no `keychain-access-groups`
    /// > entitlement is required (and adding an unnecessary one is a common cause
    /// > of `errSecMissingEntitlement`, -34018). We therefore deliberately do NOT
    /// > set `kSecAttrAccessGroup` here. The fallback, should the data-protection
    /// > keychain prove unavailable for this distribution posture, is the legacy
    /// > file-based (login) keychain — selected by dropping
    /// > `kSecUseDataProtectionKeychain`. That fallback is intentionally not wired:
    /// > resolve the entitlement question empirically on the notarized build
    /// > before changing this.
    static func base(for ref: SecretRef) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ref.service,
            kSecAttrAccount: ref.account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain: kCFBooleanTrue as Any,
        ]
    }

    /// The query for adding a new item, carrying the value and accessibility class.
    static func add(_ ref: SecretRef, data: Data) -> [CFString: Any] {
        var query = base(for: ref)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = accessibility
        return query
    }

    /// The query for reading an item's data back (single match, return the bytes).
    static func copy(_ ref: SecretRef) -> [CFString: Any] {
        var query = base(for: ref)
        query[kSecReturnData] = kCFBooleanTrue as Any
        query[kSecMatchLimit] = kSecMatchLimitOne
        return query
    }

    /// The attribute payload applied by `SecItemUpdate` when an item already exists.
    ///
    /// Only the value changes on update — never the accessibility class (see
    /// ``accessibility``).
    static func updateAttributes(data: Data) -> [CFString: Any] {
        [kSecValueData: data]
    }
}
