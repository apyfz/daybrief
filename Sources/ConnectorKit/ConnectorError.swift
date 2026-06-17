import DaybriefCore
import Foundation

/// The typed error surface for connector and OAuth operations.
///
/// Every case maps to a ``DaybriefCore/ConnectorErrorSummary/Kind`` via ``kind`` so the
/// orchestrator can fold a failure into the brief's surfaced error list. Messages are
/// kept free of secret material; the associated values carry diagnostics that must be
/// logged `.private` if logged at all.
public enum ConnectorError: Error, Sendable, Equatable {
    /// The fetch exceeded the connector's ``Connector/fetchTimeout``.
    case timedOut
    /// Authentication or authorization failed (expired/revoked token, missing scope,
    /// `invalid_grant`). `reason` is a short, redacted explanation.
    case authFailed(reason: String)
    /// A transport/network-level failure (DNS, connection, cancellation, non-2xx that
    /// isn't an auth error). `statusCode` is present for HTTP failures.
    case network(statusCode: Int?, reason: String)
    /// A response could not be decoded into the expected shape. `reason` describes the
    /// decode failure without echoing the payload.
    case decodingFailed(reason: String)
    /// The OAuth redirect could not be parsed, or returned a provider `error` param.
    case invalidRedirect(reason: String)
    /// The user (or provider) cancelled the auth flow.
    case userCancelled
    /// Anything else. `reason` is a short, redacted explanation.
    case other(reason: String)

    /// The coarse classification used to build a ``DaybriefCore/ConnectorErrorSummary``.
    public var kind: ConnectorErrorSummary.Kind {
        switch self {
        case .timedOut:
            return .timeout
        case .authFailed, .userCancelled:
            return .auth
        case .network:
            return .network
        case .decodingFailed:
            return .decode
        case .invalidRedirect, .other:
            return .other
        }
    }

    /// A short, display-safe message (already redacted of secrets).
    public var displayMessage: String {
        switch self {
        case .timedOut:
            return "The connector took too long to respond."
        case let .authFailed(reason):
            return "Authentication failed: \(reason)"
        case let .network(statusCode, reason):
            if let statusCode {
                return "Network error (HTTP \(statusCode)): \(reason)"
            }
            return "Network error: \(reason)"
        case let .decodingFailed(reason):
            return "Could not read the response: \(reason)"
        case let .invalidRedirect(reason):
            return "The sign-in redirect was invalid: \(reason)"
        case .userCancelled:
            return "Sign-in was cancelled."
        case let .other(reason):
            return reason
        }
    }

    /// Builds a ``DaybriefCore/ConnectorErrorSummary`` for `connectorId` from this error.
    public func summary(connectorId: ConnectorID) -> ConnectorErrorSummary {
        ConnectorErrorSummary(connectorId: connectorId, kind: kind, message: displayMessage)
    }
}
