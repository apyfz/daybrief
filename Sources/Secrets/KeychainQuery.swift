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
/// **file-based (login) keychain** — the correct store for Daybrief's distribution
/// posture (an *unsandboxed* Developer-ID app, never the Mac App Store).
///
/// Resolution of the design §10 open question: the data-protection keychain
/// (`kSecUseDataProtectionKeychain`) requires the app to carry a keychain access
/// group from a provisioning profile / App Sandbox; an unsandboxed or ad-hoc-signed
/// build has none, so those calls fail with `errSecMissingEntitlement` (-34018).
/// We therefore use the login keychain: do NOT set `kSecUseDataProtectionKeychain`,
/// and do NOT set `kSecAttrAccessible` (a data-protection attribute the login
/// keychain doesn't honor — mixing the two yields phantom `errSecItemNotFound`).
/// Login-keychain items are readable for the rest of the session once the user has
/// logged in (including while the screen is locked), which preserves generate-on-wake.
/// If a sandboxed Mac App Store build is ever pursued, switch to the data-protection
/// keychain (set `kSecUseDataProtectionKeychain` + `kSecAttrAccessible` + the
/// `keychain-access-groups` entitlement) behind that build.
///
/// `kSecAttrSynchronizable` is pinned to `false` so items never reach iCloud
/// Keychain (local-first / private-by-default) and the generic-password primary key
/// `(class, service, account, accessGroup, synchronizable)` stays deterministic.
enum KeychainQuery {
    /// The base primary-key query identifying exactly one generic-password item in
    /// the login keychain. Used as-is for delete/update and as the seed for add/copy.
    static func base(for ref: SecretRef) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ref.service,
            kSecAttrAccount: ref.account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
    }

    /// The query for adding a new item, carrying the value.
    static func add(_ ref: SecretRef, data: Data) -> [CFString: Any] {
        var query = base(for: ref)
        query[kSecValueData] = data
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
