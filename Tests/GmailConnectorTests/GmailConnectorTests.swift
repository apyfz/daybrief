import ConnectorKit
import DaybriefCore
import Foundation
@testable import GmailConnector
import Testing

@Suite("GmailConnector (offline)")
struct GmailConnectorTests {
    // MARK: - Helpers

    private static let fixtures = FixtureLoader(connectorId: .gmail)

    private func account(label: String = "alim@crispy.studio") -> Account {
        Account(
            connectorId: .gmail,
            label: label,
            spaceKey: "work",
            secretRef: SecretRef(service: "co.daybrief.oauth.google", account: label)
        )
    }

    private func request(_ accounts: [Account]) -> FetchRequest {
        FetchRequest(accounts: accounts, since: .distantPast, until: .distantFuture)
    }

    /// A connector whose backoff sleeps are instant, so rate-limit retries don't slow tests.
    private func connector(
        transport: any HTTPTransport,
        maxInFlightGets: Int = 6,
        backoff: BackoffPolicy = .default
    ) -> GmailConnector {
        GmailConnector(
            transport: transport,
            tokenProvider: StaticTokenProvider(token: "ya29.test-token"),
            maxInFlightGets: maxInFlightGets,
            clock: ImmediateClock(),
            backoff: backoff
        )
    }

    private func loadRawItems() throws -> [RawItem] {
        let listJSON = try Self.fixtures.json("messages-list")
        let ids = listJSON["messages"]?.array?.compactMap { $0["id"]?.string } ?? []
        return try ["message-get-1", "message-get-2", "message-get-3"].enumerated().map { index, name in
            let json = try Self.fixtures.json(name)
            return RawItem(
                id: ids[index],
                connectorId: .gmail,
                accountLabel: "alim@crispy.studio",
                json: json
            )
        }
    }

    // MARK: - normalize

    @Test("normalize maps subject/snippet/sender and unread+important into a BriefItem")
    func normalizeMapsFields() throws {
        let raw = try loadRawItems()
        let items = connector(transport: MockHTTPTransport()).normalize(raw)

        #expect(items.count == 3)
        let first = try #require(items.first)
        #expect(first.source == .gmail)
        #expect(first.type == .email)
        #expect(first.account == "alim@crispy.studio")
        #expect(first.title == "Release window moved to 10am")
        #expect(first.body?.hasPrefix("Quick heads up before standup") == true)
        #expect(first.people == ["Ada Lovelace <ada@example.com>"])
        #expect(first.urgencyHints.contains(.unread))
        // internalDate 1781000000000 ms => 2026-06-09T10:13:20Z.
        #expect(abs(first.timestamp.timeIntervalSince1970 - 1_781_000_000) < 0.001)
    }

    @Test("normalize emits .unread only when the UNREAD label is present")
    func normalizeUnreadFromLabel() throws {
        let raw = try loadRawItems()
        let items = connector(transport: MockHTTPTransport()).normalize(raw)

        // message-get-2 is IMPORTANT but read (no UNREAD label) → no unread hint.
        let read = try #require(items.first { $0.title == "Q2 invoice" })
        #expect(!read.urgencyHints.contains(.unread))

        // message-get-3 has UNREAD → unread hint present.
        let unread = try #require(items.first { $0.body == "(no body preview available)" })
        #expect(unread.urgencyHints.contains(.unread))
    }

    @Test("normalize falls back to (no subject) when the Subject header is missing")
    func normalizeNoSubjectFallback() throws {
        let raw = try loadRawItems()
        let items = connector(transport: MockHTTPTransport()).normalize(raw)

        let noSubject = try #require(items.first { $0.people == ["noreply@status.example"] })
        #expect(noSubject.title == "(no subject)")
    }

    @Test("normalize builds the best-effort #all/{id} deep link")
    func normalizeDeepLink() throws {
        let raw = try loadRawItems()
        let items = connector(transport: MockHTTPTransport()).normalize(raw)
        let first = try #require(items.first)
        #expect(first.url == URL(string: "https://mail.google.com/mail/u/0/#all/18f0a1b2c3d4e5f6"))
    }

    @Test("normalize ignores raw items from other connectors")
    func normalizeIgnoresForeignItems() {
        let foreign = RawItem(id: "x", connectorId: .slack, accountLabel: "a", json: .object([:]))
        let items = connector(transport: MockHTTPTransport()).normalize([foreign])
        #expect(items.isEmpty)
    }

    // MARK: - fetch (list then gets)

    @Test("fetch scripts list then per-id gets and tags the account label")
    func fetchListThenGets() async throws {
        let transport = MockHTTPTransport()
        try await transport.enqueue(data: Self.fixtures.data("messages-list"))
        try await transport.enqueue(data: Self.fixtures.data("message-get-1"))
        try await transport.enqueue(data: Self.fixtures.data("message-get-2"))
        try await transport.enqueue(data: Self.fixtures.data("message-get-3"))

        // maxInFlightGets=1 keeps the FIFO mock deterministic (gets dequeued in id order).
        let raw = try await connector(transport: transport, maxInFlightGets: 1)
            .fetch(request([account()]))

        #expect(raw.count == 3)
        #expect(raw.map(\.id) == ["18f0a1b2c3d4e5f6", "18f0a1b2c3d4aaaa", "18f0a1b2c3d4bbbb"])
        #expect(raw.allSatisfy { $0.connectorId == .gmail })
        #expect(raw.allSatisfy { $0.accountLabel == "alim@crispy.studio" })
        // The stashed JSON round-trips into normalize.
        #expect(raw[0].json["snippet"]?.string?.hasPrefix("Quick heads up") == true)
    }

    @Test("fetch sends the URL-encoded q query and maxResults on messages.list")
    func fetchListRequestShape() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(data: Data("{}".utf8)) // empty list → no gets

        _ = try await connector(transport: transport).fetch(request([account()]))

        let requests = await transport.recordedRequests
        let listURL = try #require(requests.first?.url)
        let components = try #require(URLComponents(url: listURL, resolvingAgainstBaseURL: false))
        #expect(components.host == "gmail.googleapis.com")
        #expect(components.path == "/gmail/v1/users/me/messages")

        let map = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a }
        )
        #expect(map["q"] == "(is:unread OR is:important) newer_than:1d")
        #expect(map["maxResults"] == "50")

        // The raw query string must be percent-encoded on the wire (spaces/parens).
        let rawQuery = try #require(listURL.query)
        #expect(!rawQuery.contains(" "))
        #expect(rawQuery.contains("newer_than"))

        // Bearer auth header is set.
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.test-token")
    }

    @Test("fetch requests format=metadata with From/Subject/Date headers on messages.get")
    func fetchGetRequestShape() async throws {
        let transport = MockHTTPTransport()
        try await transport.enqueue(data: Self.fixtures.data("messages-list"))
        try await transport.enqueue(data: Self.fixtures.data("message-get-1"))
        try await transport.enqueue(data: Self.fixtures.data("message-get-2"))
        try await transport.enqueue(data: Self.fixtures.data("message-get-3"))

        _ = try await connector(transport: transport, maxInFlightGets: 1).fetch(request([account()]))

        let requests = await transport.recordedRequests
        // First request is the list; the rest are gets.
        let getURL = try #require(requests.dropFirst().first?.url)
        let components = try #require(URLComponents(url: getURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/gmail/v1/users/me/messages/18f0a1b2c3d4e5f6")

        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "format" }?.value == "metadata")
        let metadataHeaders = items.filter { $0.name == "metadataHeaders" }.map { $0.value ?? "" }
        #expect(metadataHeaders == ["From", "Subject", "Date"])
    }

    @Test("fetch returns empty when the list response has no messages key")
    func fetchEmptyInbox() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(data: Data(#"{"resultSizeEstimate":0}"#.utf8))

        let raw = try await connector(transport: transport).fetch(request([account()]))
        #expect(raw.isEmpty)
        // No gets were attempted.
        let count = await transport.recordedRequests.count
        #expect(count == 1)
    }

    // MARK: - rate limiting / backoff

    @Test("fetch retries a 429 list response then succeeds")
    func fetchRetriesOn429() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.response(data: Data("rate limited".utf8), statusCode: 429, headers: [:], url: nil))
        await transport.enqueue(data: Data(#"{"resultSizeEstimate":0}"#.utf8))

        let raw = try await connector(transport: transport).fetch(request([account()]))
        #expect(raw.isEmpty)
        // One failed list + one retried list = two requests.
        let count = await transport.recordedRequests.count
        #expect(count == 2)
    }

    @Test("fetch retries a 403 userRateLimitExceeded body")
    func fetchRetriesOn403RateLimit() async throws {
        let body = #"{"error":{"errors":[{"reason":"userRateLimitExceeded"}],"code":403}}"#
        let transport = MockHTTPTransport()
        await transport.enqueue(.response(data: Data(body.utf8), statusCode: 403, headers: [:], url: nil))
        await transport.enqueue(data: Data(#"{"resultSizeEstimate":0}"#.utf8))

        let raw = try await connector(transport: transport).fetch(request([account()]))
        #expect(raw.isEmpty)
        let count = await transport.recordedRequests.count
        #expect(count == 2)
    }

    @Test("fetch fails fast on a plain 403 (revoked grant) without retrying")
    func fetchFailsFastOnPlain403() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.response(data: Data(#"{"error":"access_denied"}"#.utf8), statusCode: 403, headers: [:], url: nil))

        await #expect(throws: ConnectorError.self) {
            _ = try await connector(transport: transport).fetch(request([account()]))
        }
        // Only one request — no retry.
        let count = await transport.recordedRequests.count
        #expect(count == 1)
    }

    @Test("fetch gives up after maxRetries of sustained rate limiting")
    func fetchGivesUpAfterMaxRetries() async throws {
        let transport = MockHTTPTransport()
        // 1 initial + 2 retries = 3 rate-limited responses, then it should throw.
        for _ in 0 ..< 3 {
            await transport.enqueue(.response(data: Data("429".utf8), statusCode: 429, headers: [:], url: nil))
        }
        let policy = BackoffPolicy(maxRetries: 2, base: .milliseconds(1), maxDelay: .seconds(1))

        await #expect(throws: ConnectorError.self) {
            _ = try await connector(transport: transport, backoff: policy).fetch(request([account()]))
        }
        let count = await transport.recordedRequests.count
        #expect(count == 3)
    }

    @Test("Retry-After header overrides the computed backoff delay (parsed without error)")
    func fetchHonorsRetryAfter() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.response(data: Data("429".utf8), statusCode: 429, headers: ["Retry-After": "0"], url: nil))
        await transport.enqueue(data: Data(#"{"resultSizeEstimate":0}"#.utf8))

        let raw = try await connector(transport: transport).fetch(request([account()]))
        #expect(raw.isEmpty)
    }

    // MARK: - concurrency cap

    @Test("messages.get fan-out never exceeds the in-flight cap")
    func fetchRespectsConcurrencyCap() async throws {
        let cap = 3
        let total = 12
        let tracker = ConcurrencyTrackingTransport(
            cap: cap,
            totalGets: total,
            listBody: Self.listBody(idCount: total),
            getBody: Self.minimalGetBody
        )
        let conn = GmailConnector(
            transport: tracker,
            tokenProvider: StaticTokenProvider(token: "t"),
            maxInFlightGets: cap,
            clock: ImmediateClock()
        )

        let raw = try await conn.fetch(request([account()]))
        #expect(raw.count == total)

        let observedMax = await tracker.maxConcurrentGets
        #expect(observedMax <= cap)
        // And we actually parallelized up to the cap (not accidentally serialized).
        #expect(observedMax == cap)
    }

    // MARK: - fixtures-as-bytes

    private static func listBody(idCount: Int) -> Data {
        let messages = (0 ..< idCount).map { #"{"id":"msg-\#($0)","threadId":"t-\#($0)"}"# }.joined(separator: ",")
        return Data(#"{"messages":[\#(messages)]}"#.utf8)
    }

    private static let minimalGetBody = Data(#"""
    {"id":"msg","labelIds":["UNREAD"],"snippet":"x","internalDate":"1781000000000","payload":{"headers":[{"name":"Subject","value":"s"},{"name":"From","value":"a@b.c"}]}}
    """#.utf8)
}

// MARK: - Test doubles

/// A `Clock` whose `sleep` returns immediately, so backoff retries don't add real delay.
private struct ImmediateClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration = .zero
        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    var now: Instant {
        Instant()
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until _: Instant, tolerance _: Duration?) async throws {
        try Task.checkCancellation()
    }
}

/// A transport that suspends each `messages.get` long enough to observe how many run
/// concurrently, recording the peak in-flight count. The list call returns immediately.
///
/// Each get parks on a continuation until either a full batch of `cap` is in flight or
/// every remaining get has arrived (the final partial batch), then the parked batch is
/// released together — proving the connector launches up to `cap` gets in parallel and
/// never more, without deadlocking on a trailing partial batch.
private actor ConcurrencyTrackingTransport: HTTPTransport {
    private let cap: Int
    private let totalGets: Int
    private let listBody: Data
    private let getBody: Data

    private(set) var maxConcurrentGets = 0
    private var inFlightGets = 0
    private var getsArrived = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(cap: Int, totalGets: Int, listBody: Data, getBody: Data) {
        self.cap = cap
        self.totalGets = totalGets
        self.listBody = listBody
        self.getBody = getBody
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        guard url.path.contains("/messages/") else {
            return (listBody, response(for: url))
        }

        inFlightGets += 1
        getsArrived += 1
        maxConcurrentGets = max(maxConcurrentGets, inFlightGets)

        // Release when the batch is full, or when no further gets can ever arrive.
        let batchFull = inFlightGets >= cap
        let lastBatch = getsArrived >= totalGets
        if batchFull || lastBatch {
            releaseAll()
        } else {
            await withCheckedContinuation { continuations.append($0) }
        }

        inFlightGets -= 1
        return (getBody, response(for: url))
    }

    private func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func response(for url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
    }
}
