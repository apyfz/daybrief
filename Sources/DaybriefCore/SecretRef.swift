/// A stable reference to a secret stored in the Keychain.
///
/// Carries no secret material itself — only the `service`/`account` coordinates
/// the `Secrets` module uses to look up the actual token or key. Safe to persist
/// and to log (it contains no sensitive bytes).
public struct SecretRef: Sendable, Codable, Equatable, Hashable {
    /// The Keychain `kSecAttrService` value (logical namespace, e.g. `"com.daybrief.gmail.token"`).
    public let service: String
    /// The Keychain `kSecAttrAccount` value (which item within the service, e.g. an account label).
    public let account: String

    /// Creates a secret reference from its Keychain coordinates.
    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}
