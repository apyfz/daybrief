import Foundation

/// A test ``HTTPTransport`` that records requests and replays stubbed responses.
///
/// Stubs are dequeued FIFO: each ``send(_:)`` consumes the next enqueued ``Stub``.
/// Use ``enqueue(_:)`` / ``enqueue(data:statusCode:headers:url:)`` to script
/// responses and inspect ``recordedRequests`` afterwards. An `actor`, so it is
/// `Sendable` and safe to share across the concurrency boundaries it's injected into.
public actor MockHTTPTransport: HTTPTransport {
    /// A single canned outcome for one ``send(_:)`` call.
    public enum Stub: Sendable {
        /// Return this body with this status code (and optional headers).
        ///
        /// A non-2xx `statusCode` is returned as-is to the caller (it does *not*
        /// throw ``TransportError/unacceptableStatus(code:body:)``); the mock
        /// reproduces exactly what a server would send so unit tests can drive the
        /// status-handling paths of the code under test. Throwing transports should
        /// use ``failure(_:)`` instead.
        case response(data: Data, statusCode: Int, headers: [String: String], url: URL?)
        /// Throw this error instead of returning a response.
        case failure(any Error)
    }

    /// Every request that has been sent, in order.
    public private(set) var recordedRequests: [URLRequest] = []

    private var stubs: [Stub] = []

    /// Creates an empty mock transport.
    public init() {}

    /// Enqueues a stub to be returned by the next unstubbed ``send(_:)`` call.
    public func enqueue(_ stub: Stub) {
        stubs.append(stub)
    }

    /// Enqueues a successful response stub.
    public func enqueue(
        data: Data,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        url: URL? = nil
    ) {
        stubs.append(.response(data: data, statusCode: statusCode, headers: headers, url: url))
    }

    /// Enqueues an error stub.
    public func enqueueFailure(_ error: any Error) {
        stubs.append(.failure(error))
    }

    /// Removes all recorded requests and pending stubs.
    public func reset() {
        recordedRequests.removeAll()
        stubs.removeAll()
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequests.append(request)
        guard !stubs.isEmpty else {
            throw MockTransportError.noStubQueued(request)
        }
        let stub = stubs.removeFirst()
        switch stub {
        case let .failure(error):
            throw error
        case let .response(data, statusCode, headers, url):
            // A stubbed URL falls back to the request's URL, then to a placeholder
            // (a constant the URL initializer cannot fail on).
            let responseURL = url ?? request.url ?? URL(string: "https://mock.invalid")!
            guard let http = HTTPURLResponse(
                url: responseURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                throw MockTransportError.invalidStubResponse
            }
            return (data, http)
        }
    }
}

/// Errors specific to ``MockHTTPTransport``.
public enum MockTransportError: Error, Sendable {
    /// A request was sent but no stub was queued to answer it.
    case noStubQueued(URLRequest)
    /// `HTTPURLResponse` could not be constructed from a stub's fields.
    case invalidStubResponse
}
