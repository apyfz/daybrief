import ConnectorKit
import DaybriefCore
import Foundation

/// Holds the registered connectors and tracks which are enabled.
///
/// The orchestrator (``BriefGenerator``) fans out over the *enabled* connectors,
/// looked up here by ``DaybriefCore/ConnectorID``. The registry deliberately
/// stores `any Connector` existentials so `Pipeline` never imports the concrete
/// connector targets — the app composes the concrete connectors and registers
/// them here at startup (design §3, §6).
///
/// This is a value type holding immutable connector references plus an enabled
/// set; mutating helpers return a new registry so it stays `Sendable` and free of
/// shared mutable state. Lookups are last-registration-wins per id.
public struct ConnectorRegistry: Sendable {
    /// One registered connector together with its enabled flag.
    private struct Entry {
        let connector: any Connector
        var isEnabled: Bool
    }

    /// Insertion-ordered ids, so iteration order is stable and deterministic.
    private var order: [ConnectorID]
    /// Entries keyed by connector id (last registration wins).
    private var entries: [ConnectorID: Entry]

    /// Creates a registry from connectors, each enabled by default.
    ///
    /// - Parameter connectors: The connectors to register. If two share an id,
    ///   the later one replaces the earlier (its position in `order` is kept).
    public init(_ connectors: [any Connector] = []) {
        order = []
        entries = [:]
        for connector in connectors {
            register(connector)
        }
    }

    /// Registers (or replaces) a connector, enabled by default. Re-registering an
    /// id keeps its original ordering slot but replaces the connector + resets it
    /// to enabled.
    public mutating func register(_ connector: any Connector, enabled: Bool = true) {
        let id = connector.id
        if entries[id] == nil {
            order.append(id)
        }
        entries[id] = Entry(connector: connector, isEnabled: enabled)
    }

    /// Enables or disables the connector with the given id (no-op if absent).
    public mutating func setEnabled(_ enabled: Bool, for id: ConnectorID) {
        entries[id]?.isEnabled = enabled
    }

    /// The connector registered for `id`, or `nil` if none.
    public func connector(for id: ConnectorID) -> (any Connector)? {
        entries[id]?.connector
    }

    /// `true` if a connector is registered and enabled for `id`.
    public func isEnabled(_ id: ConnectorID) -> Bool {
        entries[id]?.isEnabled ?? false
    }

    /// Every registered connector, in registration order.
    public var allConnectors: [any Connector] {
        order.compactMap { entries[$0]?.connector }
    }

    /// The enabled connectors, in registration order — the orchestrator's fan-out set.
    public var enabledConnectors: [any Connector] {
        order.compactMap { id in
            guard let entry = entries[id], entry.isEnabled else { return nil }
            return entry.connector
        }
    }

    /// The ids of every registered connector, in registration order.
    public var registeredIDs: [ConnectorID] {
        order
    }
}
