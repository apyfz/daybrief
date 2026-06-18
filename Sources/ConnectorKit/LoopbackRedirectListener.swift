import Foundation
import Network
import os

/// A one-shot `127.0.0.1` HTTP listener that captures an OAuth loopback redirect.
///
/// Google's "Desktop app" OAuth client requires an `http://127.0.0.1:<port>` redirect,
/// which `ASWebAuthenticationSession` cannot receive — so this actor binds an
/// ``Network`` `NWListener` to the loopback interface on an OS-assigned ephemeral port,
/// serves exactly one request, parses the redirect query (`code`/`state`/`error`), and
/// shuts down. It is non-UI and deliberately bound to `127.0.0.1` (never `0.0.0.0`) so
/// no other machine can reach it; PKCE + `state` defend against same-machine races.
///
/// Lifecycle: ``start()`` binds and returns the `redirectURI` to use in the auth
/// request; ``waitForRedirect()`` suspends until the single request arrives (or the
/// listener fails / is cancelled); ``cancel()`` tears everything down. ``waitForRedirect()``
/// honors task cancellation.
public actor LoopbackRedirectListener {
    private let logger = Logger(subsystem: "co.crispy.daybrief", category: "LoopbackRedirectListener")

    private var listener: NWListener?

    /// Continuation resolved when the redirect arrives or the listener fails.
    private var pending: CheckedContinuation<OAuthRedirect, any Error>?
    /// A redirect that arrived before `waitForRedirect()` was awaited.
    private var bufferedResult: Result<OAuthRedirect, any Error>?
    /// Continuation resolved when the listener reaches `.ready` (or fails) during ``start()``.
    private var bindContinuation: CheckedContinuation<UInt16, any Error>?
    /// Set once the bind continuation has been resumed, so `.ready`/`.failed` only resume it once.
    private var didResolveBind = false
    /// Guards against serving more than one request / resuming twice.
    private var isFinished = false

    /// Creates an unstarted listener.
    public init() {}

    /// Binds the listener to `127.0.0.1` on an ephemeral port and starts accepting.
    ///
    /// Suspends until the listener reaches `.ready` and an ephemeral port is assigned.
    ///
    /// - Returns: The `http://127.0.0.1:<port>/` redirect URI to send in the
    ///   authorization request (byte-for-byte reused on the token exchange).
    /// - Throws: ``ConnectorError/network(statusCode:reason:)`` if binding fails.
    public func start() async throws -> URL {
        // TCP over loopback; no TLS for the local one-shot callback.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        if let options = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            options.version = .v4
        }
        // Pin the bind to the literal loopback host on an OS-assigned ephemeral port
        // (port 0) so the socket is never reachable from another machine.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ConnectorError.network(statusCode: nil, reason: "could not open loopback listener")
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handle(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }

        // Await the bound port (resolved by the state handler on .ready / .failed).
        let port = try await withCheckedThrowingContinuation { continuation in
            bindContinuation = continuation
            listener.start(queue: .global(qos: .userInitiated))
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else {
            throw ConnectorError.network(statusCode: nil, reason: "could not form redirect URI")
        }
        logger.debug("Loopback listener bound on port \(port, privacy: .public)")
        return url
    }

    /// Suspends until the single OAuth redirect arrives (or the listener fails).
    ///
    /// - Returns: The parsed ``OAuthRedirect``.
    /// - Throws: ``ConnectorError`` on failure, or `CancellationError` if the awaiting
    ///   task is cancelled (the listener is torn down on cancellation).
    public func waitForRedirect() async throws -> OAuthRedirect {
        if let buffered = bufferedResult {
            bufferedResult = nil
            return try buffered.get()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if isFinished {
                    continuation.resume(throwing: ConnectorError.invalidRedirect(reason: "listener already finished"))
                    return
                }
                pending = continuation
            }
        } onCancel: {
            Task { await self.failPending(with: CancellationError()) }
        }
    }

    /// Tears down the listener and any open connection.
    public func cancel() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    /// Hard cap on bytes buffered while waiting for the request line. The OAuth callback
    /// request line is short (a path + query + `HTTP/1.1`); this only bounds how long we
    /// keep re-arming `receive()` before giving up, so a hung/oversized client can't pin us.
    private static let maxRequestLineBytes = 64 * 1024

    private func handle(_ connection: NWConnection) {
        // Only the first request matters; ignore any extras.
        guard !isFinished else {
            connection.cancel()
            return
        }
        connection.start(queue: .global(qos: .userInitiated))
        // Start accumulating with an empty buffer; `receiveMore` re-arms until the first
        // line terminator is seen (or the cap is hit), so a TCP-split request line still parses.
        receiveMore(on: connection, accumulated: Data())
    }

    /// Issues one `receive`, appends to `accumulated`, and either parses (once the first
    /// CRLF/LF is present) or re-arms itself. A single connection can deliver the request
    /// line across several TCP segments — treating the first chunk as the whole request
    /// drops a split callback — so we loop until the line terminator arrives or the cap trips.
    private func receiveMore(on connection: NWConnection, accumulated: Data) {
        guard !isFinished else {
            connection.cancel()
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.onReceive(data: data, isComplete: isComplete, error: error, accumulated: accumulated, on: connection) }
        }
    }

    private func onReceive(data: Data?, isComplete: Bool, error: NWError?, accumulated: Data, on connection: NWConnection) {
        guard !isFinished else {
            connection.cancel()
            return
        }
        if let error {
            connection.cancel()
            finish(with: .failure(ConnectorError.network(statusCode: nil, reason: "loopback receive failed: \(error.localizedDescription)")))
            return
        }

        var buffer = accumulated
        if let data { buffer.append(data) }

        // Parse as soon as a full request line (terminated by CR or LF) is buffered.
        if Self.containsLineTerminator(buffer) {
            process(data: buffer, on: connection)
            return
        }

        // Peer closed the stream before sending a line terminator: parse whatever we have
        // (it may still be a complete, terminator-less request line) rather than re-arming
        // a receive that will never fire.
        if isComplete {
            process(data: buffer, on: connection)
            return
        }

        // Bound how much we buffer so a client that never terminates the line can't pin us.
        guard buffer.count < Self.maxRequestLineBytes else {
            Self.respond(on: connection, statusLine: "HTTP/1.1 400 Bad Request", body: "Bad request.")
            finish(with: .failure(ConnectorError.invalidRedirect(reason: "loopback request line exceeded size cap")))
            return
        }

        // No terminator yet and room remains — re-arm for the next segment of the split line.
        receiveMore(on: connection, accumulated: buffer)
    }

    private func process(data: Data, on connection: NWConnection) {
        guard let requestLine = Self.firstRequestLine(from: data) else {
            // No parseable request; responding and continuing to wait is unsafe (one-shot), so fail.
            Self.respond(on: connection, statusLine: "HTTP/1.1 400 Bad Request", body: "Bad request.")
            finish(with: .failure(ConnectorError.invalidRedirect(reason: "unparseable loopback request")))
            return
        }

        let redirect = Self.parseRedirect(fromRequestLine: requestLine)
        let body = redirect.error == nil
            ? "Daybrief is connected. You can close this window."
            : "Sign-in did not complete. You can close this window."
        Self.respond(on: connection, statusLine: "HTTP/1.1 200 OK", body: body)
        finish(with: .success(redirect))
    }

    /// Whether `data` contains an HTTP line terminator (CR or LF), i.e. at least one full
    /// request line has been received. Checked on raw bytes so a request line split across
    /// two `receive()` chunks is detected the moment its terminator lands.
    static func containsLineTerminator(_ data: Data) -> Bool {
        data.contains(where: { $0 == 0x0D || $0 == 0x0A }) // CR or LF
    }

    // MARK: - State / continuation plumbing

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            // Port assigned — resolve the bind continuation once.
            if !didResolveBind {
                didResolveBind = true
                if let port = listener?.port?.rawValue, port != 0 {
                    bindContinuation?.resume(returning: port)
                } else {
                    bindContinuation?.resume(throwing: ConnectorError.network(statusCode: nil, reason: "no port assigned"))
                }
                bindContinuation = nil
            }
        case let .failed(error):
            let mapped = ConnectorError.network(statusCode: nil, reason: "loopback listener failed: \(error.localizedDescription)")
            if !didResolveBind {
                didResolveBind = true
                bindContinuation?.resume(throwing: mapped)
                bindContinuation = nil
            }
            finish(with: .failure(mapped))
        case .cancelled:
            // If we were cancelled before the port bound, the bind continuation was never
            // resolved — resume it here so `start()` can't hang forever (continuation leak).
            if !didResolveBind {
                didResolveBind = true
                bindContinuation?.resume(throwing: CancellationError())
                bindContinuation = nil
            }
            // Only surfaces as an error if no redirect was captured first.
            if !isFinished {
                finish(with: .failure(ConnectorError.invalidRedirect(reason: "listener cancelled before redirect")))
            }
        default:
            break
        }
    }

    private func finish(with result: Result<OAuthRedirect, any Error>) {
        guard !isFinished else { return }
        isFinished = true
        listener?.cancel()
        listener = nil
        if let pending {
            self.pending = nil
            pending.resume(with: result)
        } else {
            bufferedResult = result
        }
    }

    private func failPending(with error: any Error) {
        finish(with: .failure(error))
    }

    // MARK: - HTTP parsing helpers (static, pure)

    /// Extracts the first request line (`GET /path?query HTTP/1.1`) from raw bytes.
    static func firstRequestLine(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Split on unicode scalars, not `Character`s: Swift treats a CRLF (`\r\n`) as a
        // single grapheme cluster, so a `Character`-level `== "\r" || == "\n"` test never
        // matches an HTTP line terminator and returns the whole request unsplit.
        let line = text.unicodeScalars
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .first
        return line.map { String(String.UnicodeScalarView($0)) }
    }

    /// Parses the request-target query of an HTTP request line into an ``OAuthRedirect``.
    static func parseRedirect(fromRequestLine line: String) -> OAuthRedirect {
        // "GET /?code=...&state=... HTTP/1.1"
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else {
            return OAuthRedirect(code: nil, state: nil, error: "invalid_request", errorDescription: "malformed request line")
        }
        let target = String(parts[1]) // "/?code=...&state=..."
        guard let queryStart = target.firstIndex(of: "?") else {
            return OAuthRedirect(code: nil, state: nil, error: nil, errorDescription: nil)
        }
        let query = String(target[target.index(after: queryStart)...])
        return OAuthRedirect.parse(query: query)
    }

    private static func respond(on connection: NWConnection, statusLine: String, body: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Daybrief</title></head>\
        <body style="font-family:-apple-system,system-ui,sans-serif;text-align:center;padding:3rem">\
        <p>\(body)</p></body></html>
        """
        let bodyData = Data(html.utf8)
        let response = """
        \(statusLine)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """
        var out = Data(response.utf8)
        out.append(bodyData)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
