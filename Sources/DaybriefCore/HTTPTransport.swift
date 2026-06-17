import Foundation

/// An injectable HTTP transport seam.
///
/// `ConnectorKit` and `LLMKit` depend on this rather than `URLSession` directly so
/// fetch/completion logic is unit-testable offline (see ``MockHTTPTransport``).
/// Implementations must honor cooperative cancellation.
public protocol HTTPTransport: Sendable {
    /// Sends a request and returns its body and response.
    ///
    /// Implementations should throw a ``TransportError`` (e.g. ``TransportError/unacceptableStatus(code:body:)``
    /// on a non-2xx response) rather than returning an error status to the caller.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Errors thrown by an ``HTTPTransport``.
public enum TransportError: Error, Sendable, Equatable {
    /// The response was not an `HTTPURLResponse` (e.g. a non-HTTP URL).
    case nonHTTPResponse
    /// The server returned a status code outside the 2xx range.
    ///
    /// `body` is the (possibly truncated) response body for diagnostics — callers
    /// must treat it as potentially sensitive and never log it `.public`.
    case unacceptableStatus(code: Int, body: Data)
}
