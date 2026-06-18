import DaybriefCore

/// Well-known ``SecretRef`` coordinates owned by the `Secrets` module itself.
///
/// Per-connector tokens, the BYO OAuth client id/secret, the Slack user token, and
/// the LLM API key are referenced by `SecretRef`s minted by their owning modules
/// (carried on `Account`); those are not enumerated here. This namespace holds only
/// the secrets `Secrets` provisions directly — currently the SQLCipher database key.
public extension SecretRef {
    /// The reference under which the 256-bit SQLCipher database key is stored.
    ///
    /// A single stable, app-global item (no per-account `account` axis), so the
    /// account slot is a fixed sentinel rather than a user-facing label.
    static let databaseKey = SecretRef(
        service: "co.daybrief.database-key",
        account: "default"
    )
}
