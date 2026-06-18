import DaybriefCore
import Foundation

/// A pure-Swift data source for the brief (Google Calendar, Gmail, Slack, …).
///
/// A connector is **dumb by contract**: it fetches provider payloads and normalizes
/// them into ``DaybriefCore/BriefItem``s, and does nothing else — it never calls the
/// LLM, renders, persists, or delivers. This keeps the surface small enough that a
/// future community PR (or an out-of-process/XPC runner) can satisfy it safely.
///
/// The protocol is intentionally usable as an existential (`any Connector`): it has
/// no associated types, exchanges only `Sendable` value types, and is async-throwing
/// from day one so the orchestrator can fan out over `[any Connector]` and a later
/// transport swap need not touch call sites.
public protocol Connector: Sendable {
    /// The connector's stable identifier (e.g. ``DaybriefCore/ConnectorID/gmail``).
    static var id: ConnectorID { get }

    /// The connector's id, available on an instance without naming the concrete type.
    ///
    /// Declared as a requirement (with a default implementation that forwards to
    /// ``id-swift.type.property``) so a conforming type that needs *per-instance*
    /// identity — e.g. a test stub that holds several distinct connectors under one
    /// concrete type — can override it and have the override dispatch dynamically
    /// through `any Connector`. (A protocol-extension-only member is statically
    /// dispatched, so the override would be silently ignored on an existential.)
    var id: ConnectorID { get }

    /// A human-facing name for onboarding and error copy (e.g. `"Gmail"`).
    static var displayName: String { get }

    /// How this connector authenticates (loopback OAuth, pasted token, …).
    var auth: AuthStrategy { get }

    /// The per-connector fetch budget the orchestrator races each ``fetch(_:)`` against.
    var fetchTimeout: Duration { get }

    /// Fetches raw provider payloads for the given accounts and time window.
    ///
    /// Implementations **must** honor cooperative cancellation (let `URLSession`'s
    /// async API surface `URLError.cancelled`, or poll `Task.isCancelled`) so the
    /// orchestrator's timeout race can abort a slow call. Each returned ``RawItem``
    /// stashes the undecoded provider JSON for ``normalize(_:)`` to interpret.
    func fetch(_ request: FetchRequest) async throws -> [RawItem]

    /// Maps raw provider payloads into normalized ``DaybriefCore/BriefItem``s.
    ///
    /// Pure and synchronous: decoding the stashed JSON must never touch the network.
    /// This is the primary unit-tested surface (drive it from on-disk fixtures via
    /// ``FixtureLoader``).
    func normalize(_ raw: [RawItem]) -> [BriefItem]
}

public extension Connector {
    /// The connector's id, available on an instance without naming the concrete type.
    var id: ConnectorID {
        Self.id
    }

    /// The connector's display name, available on an instance.
    var displayName: String {
        Self.displayName
    }
}
