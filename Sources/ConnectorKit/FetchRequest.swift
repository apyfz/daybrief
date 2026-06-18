import DaybriefCore
import Foundation

/// The input to a single ``Connector/fetch(_:)`` call.
///
/// Carries every enabled ``DaybriefCore/Account`` for the connector (multi-account:
/// one provider → N accounts) plus the time window to fetch over. The calendar
/// connector typically uses an extended lookahead for `until`; other connectors
/// fetch the `since...until` span directly.
public struct FetchRequest: Sendable, Equatable {
    /// Every enabled account for this connector.
    public let accounts: [Account]
    /// The start of the fetch window (inclusive).
    public let since: Date
    /// The end of the fetch window (inclusive); calendar may extend this as a lookahead.
    public let until: Date

    /// Creates a fetch request.
    public init(accounts: [Account], since: Date, until: Date) {
        self.accounts = accounts
        self.since = since
        self.until = until
    }
}
