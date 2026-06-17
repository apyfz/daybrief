import ConnectorKit
import DaybriefCore
import Foundation
@testable import GoogleCalendarConnector
import Testing

@Suite("GoogleCalendarConnector")
struct GoogleCalendarConnectorTests {
    /// Pacific timezone matches the fixture's offsets, so "today" lines up deterministically.
    private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    /// Noon on 2026-06-17 Pacific — the fixture's "today".
    private static func referenceNow() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let components = DateComponents(
            year: 2026, month: 6, day: 17, hour: 12, minute: 0, second: 0
        )
        return calendar.date(from: components)!
    }

    private static func loader() -> FixtureLoader {
        FixtureLoader(connectorId: .gcal)
    }

    private static func makeAccount(label: String = "alim@crispy.studio") -> Account {
        Account(
            connectorId: .gcal,
            label: label,
            spaceKey: "work",
            secretRef: SecretRef(service: "com.daybrief.gcal.token", account: label)
        )
    }

    private static func rawItems(from fixtureItems: [JSONValue], accountLabel: String) -> [RawItem] {
        fixtureItems.enumerated().map { index, event in
            RawItem(
                id: event["id"]?.string ?? "\(accountLabel)#\(index)",
                connectorId: .gcal,
                accountLabel: accountLabel,
                json: event
            )
        }
    }

    // MARK: - normalize

    @Test("normalize maps non-cancelled events and drops the cancelled one")
    func normalizeDropsCancelled() throws {
        let fixture = try Self.loader().json("events")
        let items = try #require(fixture["items"]?.array)
        #expect(items.count == 5) // 4 valid + 1 cancelled in the fixture

        let connector = GoogleCalendarConnector(
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let raw = Self.rawItems(from: items, accountLabel: "alim@crispy.studio")
        let briefItems = connector.normalize(raw)

        // The cancelled event is dropped → 4 remain.
        #expect(briefItems.count == 4)
        #expect(!briefItems.contains { $0.title == "Cancelled 1:1" })
        #expect(briefItems.allSatisfy { $0.source == .gcal })
        #expect(briefItems.allSatisfy { $0.type == .event })
        #expect(briefItems.allSatisfy { $0.account == "alim@crispy.studio" })
    }

    @Test("a timed event today maps fields and is tagged scheduled-today")
    func normalizeTimedEventToday() throws {
        let fixture = try Self.loader().json("events")
        let items = try #require(fixture["items"]?.array)
        let connector = GoogleCalendarConnector(
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let briefItems = connector.normalize(Self.rawItems(from: items, accountLabel: "alim@crispy.studio"))

        let standup = try #require(briefItems.first { $0.title == "Engineering Standup" })
        // Today + a hangoutLink → scheduled-today + has_video. The reader (the `self`
        // attendee) has accepted, so no needs_response; the other attendee's needsAction
        // must NOT leak in. Timed event → no all_day.
        #expect(standup.urgencyHints == [.scheduledToday, .other("has_video")])
        #expect(standup.body == "Zoom\n\nDaily sync. Bring blockers.")
        #expect(standup.url == URL(string: "https://www.google.com/calendar/event?eid=evt_standup_20260617"))
        // displayName preferred, email fallback for the attendee with no name.
        #expect(standup.people == ["Alim", "Jesse", "no-name@crispy.studio"])
        #expect(standup.timestamp == RFC3339.date(from: "2026-06-17T09:30:00-07:00"))
    }

    @Test("an all-day event today is tagged scheduled-today")
    func normalizeAllDayToday() throws {
        let fixture = try Self.loader().json("events")
        let items = try #require(fixture["items"]?.array)
        let connector = GoogleCalendarConnector(
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let briefItems = connector.normalize(Self.rawItems(from: items, accountLabel: "alim@crispy.studio"))

        let offsite = try #require(briefItems.first { $0.title == "Company Offsite Day" })
        // All-day event today → scheduled-today + all_day. No attendees / no video link.
        #expect(offsite.urgencyHints == [.scheduledToday, .other("all_day")])
        // All-day event has no location/description in the fixture → nil body.
        #expect(offsite.body == nil)
    }

    @Test("an event on another day carries no scheduled-today hint")
    func normalizeFutureEventNotToday() throws {
        let fixture = try Self.loader().json("events")
        let items = try #require(fixture["items"]?.array)
        let connector = GoogleCalendarConnector(
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let briefItems = connector.normalize(Self.rawItems(from: items, accountLabel: "alim@crispy.studio"))

        let review = try #require(briefItems.first { $0.title == "Design Review" })
        #expect(review.urgencyHints.isEmpty)
    }

    @Test("an unanswered today event with a conferenceData video gets needs_response + has_video")
    func normalizeNeedsResponseAndConferenceVideo() throws {
        let fixture = try Self.loader().json("events")
        let items = try #require(fixture["items"]?.array)
        let connector = GoogleCalendarConnector(
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            timeZone: Self.pacific
        )
        let briefItems = connector.normalize(Self.rawItems(from: items, accountLabel: "alim@crispy.studio"))

        let interview = try #require(briefItems.first { $0.title == "Candidate Interview" })
        // Today (scheduled-today), the reader's `self` attendee is needsAction
        // (needs_response), and a conferenceData entry of type video is present (has_video,
        // proving the non-hangoutLink path). Timed event → no all_day.
        #expect(interview.urgencyHints == [.scheduledToday, .other("needs_response"), .other("has_video")])
    }

    @Test("urgencyHints accumulate independently rather than replacing one another")
    func urgencyHintsAreAdditive() throws {
        // An all-day event today, with the reader's self-attendee unanswered and a hangoutLink:
        // every signal should fire, in deterministic order.
        let event: JSONValue = .object([
            "status": .string("confirmed"),
            "summary": .string("Everything"),
            "start": .object(["date": .string("2026-06-17")]),
            "hangoutLink": .string("https://meet.google.com/aaa-bbbb-ccc"),
            "attendees": .array([
                .object([
                    "email": .string("alim@crispy.studio"),
                    "responseStatus": .string("needsAction"),
                    "self": .bool(true),
                ]),
            ]),
        ])
        let start = try #require(EventStart(from: event["start"], fallbackTimeZone: Self.pacific))
        let hints = GoogleCalendarConnector.urgencyHints(for: event, start: start, now: Self.referenceNow())
        #expect(hints == [.scheduledToday, .other("all_day"), .other("needs_response"), .other("has_video")])
    }

    // MARK: - fetch

    @Test("fetch issues a Bearer-authed events.list request with the documented query")
    func fetchBuildsExpectedRequest() async throws {
        let transport = MockHTTPTransport()
        let body = try Self.loader().data("events")
        await transport.enqueue(data: body, statusCode: 200)

        let connector = GoogleCalendarConnector(
            transport: transport,
            tokenProvider: StaticTokenProvider(token: "ya29.calendar-token"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )

        let request = try FetchRequest(
            accounts: [Self.makeAccount()],
            since: #require(RFC3339.date(from: "2026-06-17T00:00:00-07:00")),
            until: #require(RFC3339.date(from: "2026-06-18T23:59:59-07:00"))
        )
        let raw = try await connector.fetch(request)

        // One request, four valid + one cancelled raw items (normalize drops the cancelled).
        let recorded = await transport.recordedRequests
        #expect(recorded.count == 1)
        let sent = try #require(recorded.first)

        let url = try #require(sent.url)
        #expect(url.scheme == "https")
        #expect(url.host == "www.googleapis.com")
        #expect(url.path == "/calendar/v3/calendars/primary/events")

        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(
            (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(query["singleEvents"] == "true")
        #expect(query["orderBy"] == "startTime")
        #expect(query["maxResults"] == "250")
        #expect(query["timeMin"]?.hasPrefix("2026-06-17T00:00:00") == true)
        #expect(query["timeMax"]?.hasPrefix("2026-06-18T23:59:59") == true)
        // No `fields` projection (dropped — a malformed mask was causing HTTP 400).
        #expect(query["fields"] == nil)

        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.calendar-token")

        // Raw items carry the connector id, account label, and provider json.
        #expect(raw.count == 5)
        #expect(raw.allSatisfy { $0.connectorId == .gcal })
        #expect(raw.allSatisfy { $0.accountLabel == "alim@crispy.studio" })
        #expect(raw.contains { $0.id == "evt_standup_20260617" })

        // End-to-end fetch → normalize drops the cancelled event.
        let normalized = connector.normalize(raw)
        #expect(normalized.count == 4)
    }

    @Test("fetch ignores accounts belonging to a different connector")
    func fetchSkipsForeignAccounts() async throws {
        let transport = MockHTTPTransport()
        let connector = GoogleCalendarConnector(
            transport: transport,
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let gmailAccount = Account(
            connectorId: .gmail,
            label: "other@crispy.studio",
            spaceKey: "work",
            secretRef: SecretRef(service: "x", account: "y")
        )
        let request = FetchRequest(
            accounts: [gmailAccount],
            since: Self.referenceNow(),
            until: Self.referenceNow()
        )
        let raw = try await connector.fetch(request)
        #expect(raw.isEmpty)
        #expect(await transport.recordedRequests.isEmpty)
    }

    @Test("fetch over two accounts issues one request each, both Bearer-authed")
    func fetchMultipleAccounts() async throws {
        let transport = MockHTTPTransport()
        let body = try Self.loader().data("events")
        await transport.enqueue(data: body, statusCode: 200)
        await transport.enqueue(data: body, statusCode: 200)

        let workAccount = Self.makeAccount(label: "alim@crispy.studio")
        let personalAccount = Self.makeAccount(label: "alim@gmail.com")
        let connector = GoogleCalendarConnector(
            transport: transport,
            tokenProvider: StaticTokenProvider(tokensByAccountID: [
                workAccount.id: "token-work",
                personalAccount.id: "token-personal",
            ]),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let request = FetchRequest(
            accounts: [workAccount, personalAccount],
            since: Self.referenceNow(),
            until: Self.referenceNow()
        )
        let raw = try await connector.fetch(request)

        let recorded = await transport.recordedRequests
        #expect(recorded.count == 2)
        let auths = recorded.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(auths.contains("Bearer token-work"))
        #expect(auths.contains("Bearer token-personal"))
        #expect(Set(raw.map(\.accountLabel)) == ["alim@crispy.studio", "alim@gmail.com"])
    }

    // MARK: - error mapping

    @Test("a 401 from the transport maps to authFailed")
    func fetchAuthError() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.failure(TransportError.unacceptableStatus(code: 401, body: Data())))

        let connector = GoogleCalendarConnector(
            transport: transport,
            tokenProvider: StaticTokenProvider(token: "expired"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let request = FetchRequest(
            accounts: [Self.makeAccount()],
            since: Self.referenceNow(),
            until: Self.referenceNow()
        )
        await #expect(throws: ConnectorError.authFailed(reason: "calendar access was denied (HTTP 401)")) {
            _ = try await connector.fetch(request)
        }
    }

    @Test("a 500 from the transport maps to a network error carrying the status code")
    func fetchServerError() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(.failure(TransportError.unacceptableStatus(code: 500, body: Data())))

        let connector = GoogleCalendarConnector(
            transport: transport,
            tokenProvider: StaticTokenProvider(token: "t"),
            dateProvider: FixedDateProvider(Self.referenceNow()),
            // Pin the connector's zone to the fixture's Pacific zone so window
            // formatting and "today" judgement are deterministic on any host.
            timeZone: Self.pacific
        )
        let request = FetchRequest(
            accounts: [Self.makeAccount()],
            since: Self.referenceNow(),
            until: Self.referenceNow()
        )
        let mapped = GoogleCalendarConnector.mapTransportError(.unacceptableStatus(code: 500, body: Data()))
        #expect(mapped.kind == .network)
        await #expect(throws: ConnectorError.self) {
            _ = try await connector.fetch(request)
        }
    }

    // MARK: - static metadata

    @Test("connector exposes the expected id, name, and loopback OAuth config")
    func staticMetadata() throws {
        #expect(GoogleCalendarConnector.id == .gcal)
        #expect(GoogleCalendarConnector.displayName == "Google Calendar")

        let connector = GoogleCalendarConnector(tokenProvider: StaticTokenProvider(token: "t"))
        // The auth strategy must be loopback OAuth (not pasted-token / custom-scheme).
        guard case .loopbackOAuth = connector.auth else {
            Issue.record("expected loopbackOAuth auth strategy")
            return
        }
        let config = try #require(connector.auth.oauthConfig)
        #expect(config.usesPKCE == true)
        #expect(config.scopes.contains("https://www.googleapis.com/auth/calendar.readonly"))
        #expect(config.scopes.contains("https://www.googleapis.com/auth/calendar.calendarlist.readonly"))
        #expect(config.authEndpoint == URL(string: "https://accounts.google.com/o/oauth2/v2/auth"))
        #expect(config.tokenEndpoint == URL(string: "https://oauth2.googleapis.com/token"))
    }
}
