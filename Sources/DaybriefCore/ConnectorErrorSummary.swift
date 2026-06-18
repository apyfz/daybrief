/// A surfaced, never-silent summary of a connector failure during brief assembly.
///
/// The orchestrator maps every connector outcome — including throws and timeouts —
/// into a partial brief plus a list of these; one dead connector never kills the brief.
public struct ConnectorErrorSummary: Sendable, Codable, Equatable, Hashable {
    /// A coarse classification of what went wrong, for UI grouping and copy.
    public enum Kind: String, Sendable, Codable, Equatable, Hashable {
        /// The connector exceeded its fetch budget.
        case timeout
        /// Authentication/authorization failed (expired/revoked token, missing scope).
        case auth
        /// A transport/network-level failure.
        case network
        /// A response could not be decoded as expected.
        case decode
        /// Anything else.
        case other
    }

    /// Which connector failed.
    public let connectorId: ConnectorID
    /// The classification of the failure.
    public let kind: Kind
    /// A human-readable message (already redacted of secrets) for display.
    public let message: String

    /// Creates a connector error summary.
    public init(connectorId: ConnectorID, kind: Kind, message: String) {
        self.connectorId = connectorId
        self.kind = kind
        self.message = message
    }
}
