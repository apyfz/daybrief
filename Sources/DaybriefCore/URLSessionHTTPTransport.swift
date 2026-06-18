import Foundation

/// The default ``HTTPTransport``, wrapping `URLSession`'s async API.
///
/// Throws ``TransportError/nonHTTPResponse`` if the response isn't HTTP and
/// ``TransportError/unacceptableStatus(code:body:)`` on any non-2xx status, so
/// callers get a typed error instead of having to inspect the status themselves.
/// `URLSession`'s async API honors cooperative cancellation (surfaces
/// `URLError.cancelled`), so no extra cancellation checks are needed here.
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport over the given session (defaults to `.shared`).
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.nonHTTPResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw TransportError.unacceptableStatus(code: http.statusCode, body: data)
        }
        return (data, http)
    }
}
