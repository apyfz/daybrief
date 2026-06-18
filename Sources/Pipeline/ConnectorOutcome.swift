import ConnectorKit
import DaybriefCore
import Foundation

/// The non-throwing result of racing one connector's `fetch` + `normalize`
/// against its ``ConnectorKit/Connector/fetchTimeout``.
///
/// The orchestrator maps *every* per-connector outcome — success, timeout, or
/// thrown error (honoring cancellation) — into one of these cases. This is the
/// mechanism that guarantees one dead or slow connector can never throw out of
/// the task group or kill the brief (design §6): the group's child tasks return
/// `ConnectorOutcome`, never throw.
public enum ConnectorOutcome: Sendable, Equatable {
    /// The connector fetched and normalized successfully.
    case success([BriefItem])
    /// The connector exceeded its ``ConnectorKit/Connector/fetchTimeout``.
    case timedOut(ConnectorID)
    /// The connector threw (auth, network, decode, cancellation, …). The summary
    /// is already redacted of secret material and ready to surface in the brief.
    case failed(ConnectorID, ConnectorErrorSummary)

    /// The normalized items this outcome produced, or `[]` for a failure/timeout.
    public var items: [BriefItem] {
        if case let .success(items) = self { return items }
        return []
    }

    /// The surfaced error summary for a failure or timeout, or `nil` on success.
    public var errorSummary: ConnectorErrorSummary? {
        switch self {
        case .success:
            return nil
        case let .timedOut(id):
            return ConnectorError.timedOut.summary(connectorId: id)
        case let .failed(_, summary):
            return summary
        }
    }
}
