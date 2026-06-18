import Foundation

/// A configured connector with its accounts and enabled state.
///
/// One ``Connection`` per connector the user has set up; it owns the connector's
/// ``Account`` list (multi-account) and whether the orchestrator should fetch it.
public struct Connection: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// Which connector this connection drives (e.g. ``ConnectorID/slack``).
    public let connectorId: ConnectorID
    /// Human-facing name for this connection.
    public let displayName: String
    /// The accounts under this connection.
    public let accounts: [Account]
    /// Whether the orchestrator should fetch this connection when assembling a brief.
    public let isEnabled: Bool

    /// Creates a connection.
    public init(
        id: UUID = UUID(),
        connectorId: ConnectorID,
        displayName: String,
        accounts: [Account],
        isEnabled: Bool
    ) {
        self.id = id
        self.connectorId = connectorId
        self.displayName = displayName
        self.accounts = accounts
        self.isEnabled = isEnabled
    }
}
