import DaybriefCore
import Foundation

/// One undecoded provider payload, produced by ``Connector/fetch(_:)`` and consumed
/// by ``Connector/normalize(_:)``.
///
/// Connectors stash the raw provider JSON in ``json`` (a ``DaybriefCore/JSONValue``)
/// during fetch and decode it during normalize. Keeping the payload as a `Sendable`
/// value (rather than an SDK object) means raw items can be recorded to fixtures and
/// crossed across an out-of-process boundary unchanged.
public struct RawItem: Sendable, Equatable, Hashable, Identifiable {
    /// A provider-stable identifier for the underlying item (e.g. a Gmail message id).
    public let id: String
    /// Which connector produced this item.
    public let connectorId: ConnectorID
    /// The label of the account this item came from (matches ``DaybriefCore/Account/label``).
    public let accountLabel: String
    /// The raw provider payload, to be decoded in ``Connector/normalize(_:)``.
    public let json: JSONValue

    /// Creates a raw item.
    public init(id: String, connectorId: ConnectorID, accountLabel: String, json: JSONValue) {
        self.id = id
        self.connectorId = connectorId
        self.accountLabel = accountLabel
        self.json = json
    }
}
