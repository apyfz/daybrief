import Foundation

/// A single connected account for a connector (one provider may have N accounts).
///
/// Token material is **never** stored here — only a ``SecretRef`` pointing at the
/// Keychain item the `Secrets` module resolves.
public struct Account: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// Which connector this account belongs to (e.g. ``ConnectorID/gmail``).
    public let connectorId: ConnectorID
    /// Human-facing label, e.g. `"alim@crispy.studio"`.
    public let label: String
    /// The ``Space/key`` this account is filed under (e.g. `"work"`).
    public let spaceKey: String
    /// Keychain reference to this account's token material.
    public let secretRef: SecretRef

    /// Creates an account.
    public init(
        id: UUID = UUID(),
        connectorId: ConnectorID,
        label: String,
        spaceKey: String,
        secretRef: SecretRef
    ) {
        self.id = id
        self.connectorId = connectorId
        self.label = label
        self.spaceKey = spaceKey
        self.secretRef = secretRef
    }
}
