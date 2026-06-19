import ConnectorKit
import DaybriefCore
import Foundation
@testable import SlackConnector
import Testing

// MARK: - Fixtures & helpers

private let loader = FixtureLoader(connectorId: .slack)

private func makeAccount(label: String = "Acme Workspace") -> Account {
    Account(
        connectorId: .slack,
        label: label,
        spaceKey: "work",
        secretRef: SecretRef(service: "co.daybrief.oauth.slack", account: label)
    )
}

private func makeConnector(transport: MockHTTPTransport, token: String = "xoxp-test-token") -> SlackConnector {
    SlackConnector(transport: transport, tokenProvider: StaticTokenProvider(token: token))
}

/// A 24h window ending now (matches how the orchestrator calls fetch).
private func dayWindow() -> (since: Date, until: Date) {
    let until = Date(timeIntervalSince1970: 1_750_125_600) // a fixed "now"
    return (until.addingTimeInterval(-86400), until)
}

// MARK: - normalize()

@Test func normalize_mentionHit_producesMentionMessage() throws {
    let search = try loader.json("search-messages")
    let match = try #require(search["messages"]?["matches"]?[0])
    let envelope = SlackRawEnvelope(origin: .mention, channelName: "engineering", message: match)
    let raw = RawItem(id: "mention:1750118400.001500", connectorId: .slack, accountLabel: "Acme", json: envelope.json)

    let items = makeConnector(transport: MockHTTPTransport()).normalize([raw])

    let item = try #require(items.first)
    #expect(items.count == 1)
    #expect(item.source == .slack)
    #expect(item.type == .message)
    #expect(item.account == "Acme")
    #expect(item.urgencyHints == [.mention])
    #expect(item.people == ["dana"])
    #expect(item.body == "<@U01ALIM> can you review the connector PR before standup?")
    #expect(item.title.contains("dana"))
    #expect(item.title.contains("#engineering"))
    #expect(item.url == URL(string: "https://acme.slack.com/archives/C01ENG/p1750118400001500"))
    // Slack ts 1750118400.001500 → epoch seconds with fraction preserved.
    #expect(abs(item.timestamp.timeIntervalSince1970 - 1_750_118_400.0015) < 0.0001)
}

@Test func normalize_dmMessage_producesUnreadMessage() throws {
    let history = try loader.json("conversations-history")
    let message = try #require(history["messages"]?[0]) // "Hey, are we still on for the 2pm sync?"
    let envelope = SlackRawEnvelope(origin: .directMessage, channelName: "D03DIRECT", message: message)
    let raw = RawItem(id: "dm:D03DIRECT:1750120000.000100", connectorId: .slack, accountLabel: "Acme", json: envelope.json)

    let items = makeConnector(transport: MockHTTPTransport()).normalize([raw])

    let item = try #require(items.first)
    #expect(item.type == .message)
    #expect(item.urgencyHints == [.unread])
    #expect(item.body == "Hey, are we still on for the 2pm sync?")
    // No resolved name on this raw envelope and no search `username`, so normalize uses a
    // neutral label rather than leaking the raw `U…` id. (fetch() resolves real names.)
    #expect(item.people == ["a teammate"])
    #expect(item.title.contains("Direct message"))
    #expect(item.url == nil) // history messages carry no permalink
}

@Test func normalize_groupDM_titleNamesGroup() throws {
    let history = try loader.json("conversations-history")
    let message = try #require(history["messages"]?[0])
    let envelope = SlackRawEnvelope(origin: .groupDM, channelName: "mpdm-alim--sam--dana-1", message: message)
    let raw = RawItem(id: "dm:G05GROUP:1750120000.000100", connectorId: .slack, accountLabel: "Acme", json: envelope.json)

    let item = try #require(makeConnector(transport: MockHTTPTransport()).normalize([raw]).first)
    #expect(item.urgencyHints == [.unread])
    #expect(item.title.contains("group DM"))
}

@Test func normalize_isDeterministic_sameRawIDSameUUID() throws {
    let search = try loader.json("search-messages")
    let match = try #require(search["messages"]?["matches"]?[0])
    let envelope = SlackRawEnvelope(origin: .mention, channelName: "engineering", message: match)
    let raw = RawItem(id: "mention:1750118400.001500", connectorId: .slack, accountLabel: "Acme", json: envelope.json)

    let connector = makeConnector(transport: MockHTTPTransport())
    let first = try #require(connector.normalize([raw]).first)
    let second = try #require(connector.normalize([raw]).first)
    #expect(first.id == second.id)
}

@Test func normalize_malformedEnvelope_isDropped() {
    let raw = RawItem(id: "x", connectorId: .slack, accountLabel: "Acme", json: .object(["nope": .bool(true)]))
    #expect(makeConnector(transport: MockHTTPTransport()).normalize([raw]).isEmpty)
}

// MARK: - fetch()

@Test func fetch_searchAndDMs_viaMockTransport() async throws {
    let transport = MockHTTPTransport()
    // FIFO order: auth.test (resolve self), search.messages, conversations.list, then
    // per DM channel a conversations.info (unread count) followed — when unread > 0 —
    // by conversations.history (the list fixture has 2 channels: D03DIRECT + G05GROUP,
    // and the info fixture reports 3 unread for each).
    try await transport.enqueue(data: loader.data("auth-test"))
    try await transport.enqueue(data: loader.data("search-messages"))
    try await transport.enqueue(data: loader.data("conversations-list"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))
    // Sender-name resolution: the surfaced DM sender (U04SAM, no `username`) is resolved
    // once via users.info. (The authed user's own message is dropped, so only U04SAM.)
    try await transport.enqueue(data: loader.data("users-info"))

    let window = dayWindow()
    let raw = try await makeConnector(transport: transport)
        .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))

    // 2 mentions (both fixture matches name <@U01ALIM>) + DMs: each channel's only non-own,
    // recent, non-system message (the authed user's own message + the channel_join are
    // dropped) → 1 per channel × 2 channels = 2.
    let mentions = raw.filter { $0.id.hasPrefix("mention:") }
    let dms = raw.filter { $0.id.hasPrefix("dm:") }
    #expect(mentions.count == 2)
    #expect(dms.count == 2)

    let requests = await transport.recordedRequests
    // auth.test, search.messages, conversations.list, (info + history) × 2 channels, users.info.
    #expect(requests.count == 8)

    // First request resolves the authed user via auth.test (with a Bearer token).
    let authURL = try #require(requests.first?.url?.absoluteString)
    #expect(authURL.contains("auth.test"))
    #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer xoxp-test-token")

    // Second request hits search.messages, narrowed to the authed user's @handle.
    let searchURL = try #require(requests[1].url?.absoluteString)
    #expect(searchURL.contains("search.messages"))
    #expect(searchURL.contains("query=after"))
    // The `after:` filter is anchored to the day before the window's `since` (UTC).
    #expect(searchURL.contains(SlackConnector.searchDay(forDayBefore: window.since)))
    // The query is narrowed to the user's @handle so it isn't a blanket
    // "everything after this date" sweep. URLComponents leaves "@" un-encoded in the
    // query component and encodes the separating space as "%20".
    #expect(searchURL.contains("%20@alim"))
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer xoxp-test-token")

    #expect(try #require(requests[2].url?.absoluteString).contains("conversations.list"))
    // Each channel is probed with conversations.info before its history is read.
    let infoURL = try #require(requests[3].url?.absoluteString)
    #expect(infoURL.contains("conversations.info"))
    #expect(infoURL.contains("channel=D03DIRECT"))
    let historyURL = try #require(requests[4].url?.absoluteString)
    #expect(historyURL.contains("conversations.history"))
    #expect(historyURL.contains("channel=D03DIRECT"))
    // DM history is unread-based now: no oldest/latest window, just the unread tail.
    #expect(!historyURL.contains("oldest="))
    #expect(!historyURL.contains("latest="))
    #expect(historyURL.contains("limit=3")) // min(unread=3, historyLimit)
    #expect(try #require(requests[5].url?.absoluteString).contains("conversations.info"))
    #expect(try #require(requests[6].url?.absoluteString).contains("conversations.history"))
}

@Test func fetch_dmWithZeroUnread_isSkippedNoHistoryCall() async throws {
    let transport = MockHTTPTransport()
    // auth.test returns no user_id so mentions are skipped — this test is only about
    // the unread gate. The list fixture has two channels: the first reports 0 unread
    // (must be skipped with no history call), the second reports 3 unread.
    try await transport.enqueue(data: loader.data("auth-test-no-user"))
    try await transport.enqueue(data: loader.data("conversations-list"))
    try await transport.enqueue(data: loader.data("conversations-info-read")) // D03DIRECT: 0 unread → skip
    try await transport.enqueue(data: loader.data("conversations-info")) // G05GROUP: 3 unread → read
    try await transport.enqueue(data: loader.data("conversations-history"))
    // No identity (auth-test-no-user) → own-message filter can't apply, so both senders
    // (U04SAM, U01ALIM) surface and each is resolved once via users.info.
    try await transport.enqueue(data: loader.data("users-info"))
    try await transport.enqueue(data: loader.data("users-info"))

    let window = dayWindow()
    let raw = try await makeConnector(transport: transport)
        .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))

    // Only the second (unread) channel contributes DM items; the read channel adds none.
    let dms = raw.filter { $0.id.hasPrefix("dm:") }
    #expect(dms.count == 2) // G05GROUP's two real messages (channel_join subtype skipped)
    #expect(dms.allSatisfy { $0.id.hasPrefix("dm:G05GROUP:") })

    let requests = await transport.recordedRequests
    // auth.test, list, info(read)→skip, info(unread)→history, then users.info × 2 senders = 7.
    #expect(requests.count == 7)
    let urls = requests.compactMap { $0.url?.absoluteString }
    // Exactly one history call was made — the read channel never triggered one.
    #expect(urls.filter { $0.contains("conversations.history") }.count == 1)
    #expect(urls.filter { $0.contains("conversations.info") }.count == 2)
    // The single history call targets the unread channel, not the read one.
    let historyURL = try #require(urls.first { $0.contains("conversations.history") })
    #expect(historyURL.contains("channel=G05GROUP"))
    #expect(!urls.contains { $0.contains("conversations.history") && $0.contains("channel=D03DIRECT") })
}

@Test func fetch_thenNormalize_endToEnd() async throws {
    let transport = MockHTTPTransport()
    try await transport.enqueue(data: loader.data("auth-test"))
    try await transport.enqueue(data: loader.data("search-messages"))
    try await transport.enqueue(data: loader.data("conversations-list"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))

    let window = dayWindow()
    let connector = makeConnector(transport: transport)
    let raw = try await connector
        .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))
    let items = connector.normalize(raw)

    #expect(items.allSatisfy { $0.source == .slack && $0.type == .message })
    #expect(items.contains { $0.urgencyHints == [.mention] })
    #expect(items.contains { $0.urgencyHints == [.unread] })
}

// MARK: - honest mention labeling

@Test func fetch_searchMatches_onlyTrueMentionsLabeledMention() async throws {
    let transport = MockHTTPTransport()
    // auth.test resolves self (U01ALIM / @alim), then a search whose 3 matches include
    // two fuzzy non-mentions ("alim shipped…", "the alimony deadline…") that name the
    // handle as a word but carry no <@U01ALIM> token, plus one real mention.
    try await transport.enqueue(data: loader.data("auth-test"))
    try await transport.enqueue(data: loader.data("search-messages-fuzzy"))
    try await transport.enqueue(data: loader.data("conversations-list"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))

    let window = dayWindow()
    let raw = try await makeConnector(transport: transport)
        .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))

    // Only the single match that actually contains <@U01ALIM> is surfaced as a mention;
    // the two fuzzy word-matches are dropped, not mislabeled.
    let mentions = raw.filter { $0.id.hasPrefix("mention:") }
    #expect(mentions.count == 1)
    #expect(mentions.first?.id == "mention:1750118400.001500")
}

// MARK: - graceful degradation when identity is unknown

@Test func fetch_authTestWithoutUserID_skipsMentionsReturnsDMsOnly() async throws {
    let transport = MockHTTPTransport()
    // auth.test returns ok:true but no user_id → can't narrow/verify mentions. The
    // connector must NOT call search.messages and must NOT mislabel anything; it falls
    // back to DMs only.
    try await transport.enqueue(data: loader.data("auth-test-no-user"))
    try await transport.enqueue(data: loader.data("conversations-list"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))
    try await transport.enqueue(data: loader.data("conversations-info"))
    try await transport.enqueue(data: loader.data("conversations-history"))
    // No identity → own-message filter can't apply; both distinct senders resolved via users.info.
    try await transport.enqueue(data: loader.data("users-info"))
    try await transport.enqueue(data: loader.data("users-info"))

    let window = dayWindow()
    let raw = try await makeConnector(transport: transport)
        .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))

    #expect(raw.filter { $0.id.hasPrefix("mention:") }.isEmpty)
    #expect(raw.filter { $0.id.hasPrefix("dm:") }.count == 4)

    // No search.messages request: auth.test, list, (info + history) × 2 channels, then
    // users.info × 2 senders = 8.
    let requests = await transport.recordedRequests
    #expect(requests.count == 8)
    #expect(try #require(requests.first?.url?.absoluteString).contains("auth.test"))
    #expect(requests.allSatisfy { !($0.url?.absoluteString.contains("search.messages") ?? false) })
}

// MARK: - ok:false error path

@Test func fetch_okFalse_notAuthed_mapsToAuthFailedKind() async throws {
    let transport = MockHTTPTransport()
    try await transport.enqueue(data: loader.data("error-not-authed"), statusCode: 200)
    let window = dayWindow()

    do {
        _ = try await makeConnector(transport: transport)
            .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))
        Issue.record("Expected fetch to throw on ok:false")
    } catch let error as ConnectorError {
        #expect(error.kind == .auth)
    }
}

@Test func fetch_ratelimited429_surfacesDistributedAppHint() async throws {
    let transport = MockHTTPTransport()
    // URLSessionHTTPTransport throws on 429; the mock reproduces a throwing transport.
    await transport.enqueueFailure(TransportError.unacceptableStatus(code: 429, body: Data()))
    let window = dayWindow()

    do {
        _ = try await makeConnector(transport: transport)
            .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))
        Issue.record("Expected fetch to throw on 429")
    } catch let ConnectorError.network(statusCode, reason) {
        #expect(statusCode == 429)
        #expect(reason.lowercased().contains("internal"))
    }
}

@Test func fetch_okFalseRatelimitedBody_surfacesDistributedAppHint() async throws {
    let transport = MockHTTPTransport()
    // Slack can also signal throttling in-body with ok:false / error:"ratelimited".
    let body = Data(#"{"ok":false,"error":"ratelimited"}"#.utf8)
    await transport.enqueue(data: body, statusCode: 200)
    let window = dayWindow()

    do {
        _ = try await makeConnector(transport: transport)
            .fetch(FetchRequest(accounts: [makeAccount()], since: window.since, until: window.until))
        Issue.record("Expected fetch to throw on ratelimited")
    } catch let ConnectorError.network(statusCode, reason) {
        #expect(statusCode == 429)
        #expect(reason.lowercased().contains("internal"))
    }
}

// MARK: - auth strategy

@Test func auth_isPastedUserToken_withXoxpHint() throws {
    let connector = makeConnector(transport: MockHTTPTransport())
    let spec = try #require(connector.auth.tokenSpec)
    #expect(spec.tokenPrefixHint == "xoxp-")
    #expect(spec.validatesPrefix(of: "xoxp-abc") == true)
    #expect(spec.validatesPrefix(of: "xoxb-abc") == false) // reject bot tokens
    #expect(SlackConnector.id == .slack)
    #expect(SlackConnector.displayName == "Slack")
}
