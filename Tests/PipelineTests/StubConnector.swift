import ConnectorKit
import DaybriefCore
import Foundation

/// A scriptable ``Connector`` for orchestrator tests — no network.
///
/// Configurable to succeed (returning canned raw items), throw a specific
/// ``ConnectorError``, or hang past its timeout (driven by an injected clock in
/// ``BriefGenerator``). Each instance carries its own id so a registry can hold
/// several distinct stubs.
struct StubConnector: Connector {
    enum Behavior {
        /// Return these raw items immediately.
        case succeed([RawItem])
        /// Throw this connector error.
        case throwError(ConnectorError)
        /// Sleep `for` longer than the fetch timeout so the timeout race wins.
        /// The sleep honors cooperative cancellation.
        case hang(for: Duration)
    }

    /// The protocol's static id is a placeholder; each instance carries its own
    /// ``instanceID`` and overrides the instance `id` so a registry can hold
    /// several distinct stubs (the default `var id { Self.id }` would otherwise
    /// report the same value for all of them).
    static let id: ConnectorID = "stub"
    static let displayName = "Stub"

    let instanceID: ConnectorID
    let behavior: Behavior
    let auth: AuthStrategy = .pastedUserToken(TokenSpec(setupInstructions: "stub"))
    let fetchTimeout: Duration

    /// Per-instance id, overriding the default static-backed `var id`.
    var id: ConnectorID {
        instanceID
    }

    init(id: ConnectorID, behavior: Behavior, fetchTimeout: Duration = .seconds(5)) {
        instanceID = id
        self.behavior = behavior
        self.fetchTimeout = fetchTimeout
    }

    func fetch(_: FetchRequest) async throws -> [RawItem] {
        switch behavior {
        case let .succeed(items):
            return items
        case let .throwError(error):
            throw error
        case let .hang(duration):
            try await ContinuousClock().sleep(for: duration)
            return []
        }
    }

    func normalize(_ raw: [RawItem]) -> [BriefItem] {
        raw.map { item in
            BriefItem(
                id: UUID(),
                source: item.connectorId,
                account: item.accountLabel,
                space: "work",
                type: .message,
                title: item.json["title"]?.string ?? "Untitled",
                body: item.json["body"]?.string,
                people: [],
                timestamp: Date(timeIntervalSince1970: 0),
                url: nil,
                urgencyHints: []
            )
        }
    }
}

extension StubConnector {
    /// A success stub producing one raw item with the given title.
    static func succeeding(id: ConnectorID, title: String) -> StubConnector {
        let raw = RawItem(
            id: "\(id.rawValue)-1",
            connectorId: id,
            accountLabel: "\(id.rawValue)@example.com",
            json: .object(["title": .string(title)])
        )
        return StubConnector(id: id, behavior: .succeed([raw]))
    }
}
