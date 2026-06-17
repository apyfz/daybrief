import ConnectorKit
import DaybriefCore
import Foundation
import os

/// Reads recent unread/important mail from one or more Gmail accounts.
///
/// **Auth.** Bring-your-own Google *Desktop* OAuth client over a `127.0.0.1` loopback
/// redirect + PKCE (``AuthStrategy/loopbackOAuth(_:)``). The single requested scope is
/// `gmail.readonly` — restricted, but `gmail.metadata` is *also* restricted (no lighter
/// escape), so there is nothing to gain by narrowing further. Onboarding must drive the
/// user's own client to "In production" to avoid the 7-day refresh-token expiry that
/// "Testing"-status clients suffer (see the design doc, §7.2).
///
/// **Fetch.** Per account: one `users.messages.list` with
/// `q=(is:unread OR is:important) newer_than:1d&maxResults=50`, then a fan-out of
/// `users.messages.get?format=metadata` (From/Subject/Date headers only — `snippet` is
/// still returned in metadata mode, so v0 never pulls the message body). The list→get
/// fan-out is N+1 and Gmail enforces a per-user 250-units/sec cap (list=get=5 units), so
/// the per-account get fan-out is bounded to ``maxInFlightGets`` and retries on HTTP
/// `429`/`403` with truncated exponential backoff.
///
/// **Multi-account.** Each ``DaybriefCore/Account`` has its own token, its own `/users/me`,
/// and its own rate budget; accounts run sequentially here (a single user's 24h window is
/// tiny) while each account's get fan-out stays independently bounded.
public struct GmailConnector: Connector {
    public static let id: ConnectorID = .gmail
    public static let displayName = "Gmail"

    /// The Google authorization endpoint shared with the calendar connector.
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    /// The Google token endpoint shared with the calendar connector.
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    /// The Gmail read scope. Restricted; `gmail.metadata` is also restricted, so this is the floor.
    static let scopes = ["https://www.googleapis.com/auth/gmail.readonly"]

    private static let logger = Logger(subsystem: "co.daybrief.connector", category: "gmail")

    public let auth: AuthStrategy
    public let fetchTimeout: Duration

    /// The maximum number of concurrent `messages.get` calls per account (Gmail's
    /// 250-units/sec per-user cap divided by 5 units/get is ~50 — staying near 6 keeps
    /// us comfortably under budget while still parallelizing the N+1 fan-out).
    let maxInFlightGets: Int
    /// How many `maxResults` to request from `messages.list`.
    let maxResults: Int

    private let transport: any HTTPTransport
    private let tokenProvider: any TokenProvider
    private let clock: any Clock<Duration>
    private let backoff: BackoffPolicy

    /// Creates a Gmail connector.
    ///
    /// - Parameters:
    ///   - transport: The HTTP seam (defaults to a real `URLSession`; tests inject a mock).
    ///   - tokenProvider: Supplies a valid bearer token per account.
    ///   - clientID: The user's own Google *Desktop* OAuth client id (empty until onboarding wires it).
    ///   - clientSecret: The Desktop client's secret, if Google issued one (not confidential for an installed app).
    ///   - fetchTimeout: The orchestrator's per-connector budget.
    ///   - maxInFlightGets: Concurrency cap for the `messages.get` fan-out.
    ///   - maxResults: `messages.list` page size.
    ///   - clock: Sleep clock for backoff (inject a test clock for determinism).
    ///   - backoff: Retry policy for `429`/`403` rate-limit responses.
    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        tokenProvider: any TokenProvider,
        clientID: String = "",
        clientSecret: String? = nil,
        fetchTimeout: Duration = .seconds(20),
        maxInFlightGets: Int = 6,
        maxResults: Int = 50,
        clock: any Clock<Duration> = ContinuousClock(),
        backoff: BackoffPolicy = .default
    ) {
        auth = .loopbackOAuth(
            OAuthConfig(
                authEndpoint: Self.authEndpoint,
                tokenEndpoint: Self.tokenEndpoint,
                clientID: clientID,
                clientSecret: clientSecret,
                scopes: Self.scopes,
                usesPKCE: true
            )
        )
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.fetchTimeout = fetchTimeout
        self.maxInFlightGets = max(1, maxInFlightGets)
        self.maxResults = max(1, maxResults)
        self.clock = clock
        self.backoff = backoff
    }

    // MARK: - Fetch

    public func fetch(_ request: FetchRequest) async throws -> [RawItem] {
        var items: [RawItem] = []
        for account in request.accounts where account.connectorId == Self.id {
            try Task.checkCancellation()
            let token = try await tokenProvider.accessToken(for: account)
            let messageIDs = try await listMessageIDs(token: token)
            let messages = try await fetchMessages(ids: messageIDs, token: token)
            for message in messages {
                items.append(
                    RawItem(
                        id: message.id,
                        connectorId: Self.id,
                        accountLabel: account.label,
                        json: message.json
                    )
                )
            }
        }
        return items
    }

    /// Builds the `messages.list` URL with the URL-encoded search query.
    func listURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gmail.googleapis.com"
        components.path = "/gmail/v1/users/me/messages"
        components.queryItems = [
            // `(is:unread OR is:important) newer_than:1d` — `URLComponents` percent-encodes the
            // value, so the literal query is set as-is and serialized safely.
            URLQueryItem(name: "q", value: "(is:unread OR is:important) newer_than:1d"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        // `URLComponents` cannot fail to produce a URL from these fixed, valid pieces.
        return components.url!
    }

    /// Builds the `messages.get?format=metadata` URL for one message id.
    func messageURL(id: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gmail.googleapis.com"
        components.path = "/gmail/v1/users/me/messages/\(id)"
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        return components.url!
    }

    private func listMessageIDs(token: String) async throws -> [String] {
        let data = try await getWithBackoff(url: listURL(), token: token)
        let json = try decodeJSON(data, context: "messages.list")
        guard let messages = json["messages"]?.array else {
            // Empty inbox windows return no `messages` key at all — that is success, not failure.
            return []
        }
        return messages.compactMap { $0["id"]?.string }
    }

    /// Fans out `messages.get` over `ids`, bounded to ``maxInFlightGets`` concurrent calls,
    /// preserving input order in the result.
    private func fetchMessages(ids: [String], token: String) async throws -> [GmailMessage] {
        guard !ids.isEmpty else { return [] }
        let cap = min(maxInFlightGets, ids.count)

        return try await withThrowingTaskGroup(of: (Int, GmailMessage).self) { group in
            var next = 0
            // Prime the pump with `cap` tasks, then add one more each time a child finishes —
            // this keeps at most `cap` `messages.get` calls in flight at any instant.
            while next < cap {
                let index = next
                let id = ids[index]
                group.addTask { try (index, await self.fetchMessage(id: id, token: token)) }
                next += 1
            }

            var results: [(Int, GmailMessage)] = []
            results.reserveCapacity(ids.count)
            while let finished = try await group.next() {
                results.append(finished)
                if next < ids.count {
                    let index = next
                    let id = ids[index]
                    group.addTask { try (index, await self.fetchMessage(id: id, token: token)) }
                    next += 1
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func fetchMessage(id: String, token: String) async throws -> GmailMessage {
        let data = try await getWithBackoff(url: messageURL(id: id), token: token)
        let json = try decodeJSON(data, context: "messages.get")
        return GmailMessage(json: json)
    }

    // MARK: - Transport + backoff

    /// Sends an authorized GET, retrying on `429`/`403` rate-limit responses with truncated
    /// exponential backoff. Honors cancellation between attempts.
    private func getWithBackoff(url: URL, token: String) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let result = try await send(url: url, token: token)
            switch classify(result) {
            case let .ok(data):
                return data
            case let .rateLimited(retryAfter):
                guard attempt < backoff.maxRetries else {
                    throw ConnectorError.network(
                        statusCode: result.statusCode,
                        reason: "Gmail rate limit exceeded after \(backoff.maxRetries) retries."
                    )
                }
                let delay = retryAfter ?? backoff.delay(forAttempt: attempt)
                try await clock.sleep(for: delay)
                attempt += 1
            case let .auth(reason):
                throw ConnectorError.authFailed(reason: reason)
            case let .http(code, reason):
                throw ConnectorError.network(statusCode: code, reason: reason)
            }
        }
    }

    /// One transport round-trip, mapping the two transport behaviors (a thrown
    /// ``ConnectorKit/TransportError`` from the real transport vs. a returned non-2xx status
    /// from ``DaybriefCore/MockHTTPTransport``) into one ``HTTPResult``.
    private func send(url: URL, token: String) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await transport.send(request)
            return HTTPResult(statusCode: response.statusCode, data: data, headers: response.allHeaderFields)
        } catch let TransportError.unacceptableStatus(code, body) {
            return HTTPResult(statusCode: code, data: body, headers: [:])
        } catch is CancellationError {
            throw ConnectorError.timedOut
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw ConnectorError.timedOut
        } catch {
            throw ConnectorError.network(statusCode: nil, reason: "Transport failure.")
        }
    }

    private func classify(_ result: HTTPResult) -> ResponseOutcome {
        switch result.statusCode {
        case 200 ..< 300:
            return .ok(result.data)
        case 429:
            return .rateLimited(retryAfter: result.retryAfter)
        case 403:
            // 403 is rate-limiting only when Google tags it userRateLimitExceeded/rateLimitExceeded;
            // a plain 403 (revoked grant, missing scope) is a hard auth failure that must fail fast.
            if result.isRateLimitReason {
                return .rateLimited(retryAfter: result.retryAfter)
            }
            // A hard 403 is almost always the Gmail API not being enabled in the user's
            // own Cloud project (or read access not granted). Google's body names which —
            // turn it into an actionable reason.
            let body = String(decoding: result.data.prefix(400), as: UTF8.self)
            let reason: String
            if body.localizedCaseInsensitiveContains("has not been used")
                || body.localizedCaseInsensitiveContains("accessNotConfigured")
                || body.localizedCaseInsensitiveContains("is disabled")
            {
                reason = "the Gmail API isn't enabled in your Google Cloud project — enable it (APIs & Services → Library → Gmail API), then refresh"
            } else if body.localizedCaseInsensitiveContains("insufficient")
                || body.localizedCaseInsensitiveContains("scope")
            {
                reason = "Gmail read access wasn't granted — reconnect Gmail and allow read access"
            } else {
                reason = "Gmail denied access (HTTP 403) — check the Gmail API is enabled and reconnect"
            }
            return .auth(reason: reason)
        case 401:
            return .auth(reason: "Token expired or invalid (HTTP 401).")
        default:
            return .http(code: result.statusCode, reason: "Unexpected Gmail status \(result.statusCode).")
        }
    }

    private func decodeJSON(_ data: Data, context: String) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ConnectorError.decodingFailed(reason: "Malformed \(context) response.")
        }
    }

    // MARK: - Normalize

    public func normalize(_ raw: [RawItem]) -> [BriefItem] {
        raw.compactMap { item -> BriefItem? in
            guard item.connectorId == Self.id else { return nil }
            let message = GmailMessage(json: item.json)
            return GmailNormalizer.briefItem(from: message, accountLabel: item.accountLabel)
        }
    }
}

// MARK: - Internal HTTP result handling

/// A status-normalized HTTP round-trip, hiding whether the body arrived via a returned
/// non-2xx response (mock) or a thrown ``ConnectorKit/TransportError`` (real transport).
private struct HTTPResult {
    let statusCode: Int
    let data: Data
    let headers: [AnyHashable: Any]

    /// The `Retry-After` header parsed as whole seconds, if present and numeric.
    var retryAfter: Duration? {
        guard let value = headerValue("Retry-After"), let seconds = Int(value.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return .seconds(max(0, seconds))
    }

    /// Whether a `403` body carries a Gmail rate-limit reason (so it should be retried, not failed).
    var isRateLimitReason: Bool {
        guard let body = String(data: data, encoding: .utf8) else { return false }
        return body.contains("userRateLimitExceeded") || body.contains("rateLimitExceeded")
    }

    private func headerValue(_ name: String) -> String? {
        for (key, value) in headers {
            if let key = key as? String, key.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String
            }
        }
        return nil
    }
}

private enum ResponseOutcome {
    case ok(Data)
    case rateLimited(retryAfter: Duration?)
    case auth(reason: String)
    case http(code: Int, reason: String)
}

// MARK: - Backoff

/// Truncated exponential backoff for Gmail `429`/`403` rate-limit responses.
public struct BackoffPolicy: Sendable, Equatable {
    /// How many times to retry a rate-limited request before giving up.
    public let maxRetries: Int
    /// The base delay; attempt `n` waits `base * 2^n`, capped at ``maxDelay``.
    public let base: Duration
    /// The ceiling on any single backoff delay.
    public let maxDelay: Duration

    public init(maxRetries: Int, base: Duration, maxDelay: Duration) {
        self.maxRetries = maxRetries
        self.base = base
        self.maxDelay = maxDelay
    }

    /// The (zero-jitter, truncated) delay for a given zero-based attempt index.
    func delay(forAttempt attempt: Int) -> Duration {
        let factor = 1 << min(attempt, 16)
        let scaled = base * factor
        return scaled < maxDelay ? scaled : maxDelay
    }

    /// A couple of retries with a short base and a sane ceiling.
    public static let `default` = BackoffPolicy(maxRetries: 2, base: .milliseconds(500), maxDelay: .seconds(32))
}
