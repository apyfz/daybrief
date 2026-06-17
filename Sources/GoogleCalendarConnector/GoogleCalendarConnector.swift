import ConnectorKit
import DaybriefCore
import Foundation

/// Reads events from Google Calendar via the Calendar API v3 `events.list` endpoint.
///
/// Auth is the BYO-client loopback OAuth flow (see ``ConnectorKit/AuthStrategy/loopbackOAuth(_:)``):
/// each user supplies their own Google **Desktop** OAuth client, and tokens are minted by
/// `AppFeature`'s OAuth machinery and handed to ``fetch(_:)`` through a ``ConnectorKit/TokenProvider``.
///
/// `fetch` issues one `events.list` request per account against the `primary` calendar over the
/// request window (`singleEvents=true&orderBy=startTime`, RFC3339 `timeMin`/`timeMax`), stashing
/// each raw event into a ``ConnectorKit/RawItem``. `normalize` maps every non-cancelled event into a
/// ``DaybriefCore/BriefItem`` of type ``DaybriefCore/ItemType/event``.
///
/// The type is a value (`Sendable`) and runs `nonisolated`; it never touches the LLM, render,
/// persistence, or delivery layers (connectors are dumb by contract).
public struct GoogleCalendarConnector: Connector {
    public static let id: ConnectorID = .gcal
    public static let displayName = "Google Calendar"

    /// The calendar id queried per account. v0 reads only the user's `primary` calendar;
    /// per-calendar selection (via `calendar.calendarlist.readonly`) is a later refinement.
    private static let calendarId = "primary"

    private let transport: any HTTPTransport
    private let tokenProvider: any TokenProvider
    private let dateProvider: any DateProvider
    private let timeZone: TimeZone
    private let timeoutBudget: Duration

    public var auth: AuthStrategy {
        .loopbackOAuth(
            OAuthConfig(
                authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                // Empty at construction; filled at wiring time from the user's BYO Desktop client.
                clientID: "",
                scopes: [
                    "https://www.googleapis.com/auth/calendar.readonly",
                    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
                ],
                usesPKCE: true
            )
        )
    }

    public var fetchTimeout: Duration {
        timeoutBudget
    }

    /// Creates a Google Calendar connector.
    ///
    /// - Parameters:
    ///   - transport: HTTP seam (defaults to ``DaybriefCore/URLSessionHTTPTransport``); inject
    ///     ``DaybriefCore/MockHTTPTransport`` in tests.
    ///   - tokenProvider: supplies a valid Bearer access token per account.
    ///   - dateProvider: source of "now", used to tag events that fall on today
    ///     (defaults to ``DaybriefCore/SystemDateProvider``).
    ///   - timeZone: the reader's local zone, used to build the fetch window's RFC3339
    ///     bounds and to judge whether an event (notably an all-day, zone-less event)
    ///     falls on "today". Injected (default `.current`) so behavior is deterministic
    ///     and not tied to the wall-clock zone of the host running the code.
    ///   - fetchTimeout: the orchestrator's per-fetch budget (Calendar's quota is generous,
    ///     so a short budget is fine).
    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        tokenProvider: any TokenProvider,
        dateProvider: any DateProvider = SystemDateProvider(),
        timeZone: TimeZone = .current,
        fetchTimeout: Duration = .seconds(15)
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.dateProvider = dateProvider
        self.timeZone = timeZone
        timeoutBudget = fetchTimeout
    }

    // MARK: - Fetch

    public func fetch(_ request: FetchRequest) async throws -> [RawItem] {
        var items: [RawItem] = []
        for account in request.accounts where account.connectorId == Self.id {
            try Task.checkCancellation()
            let token = try await tokenProvider.accessToken(for: account)
            let raw = try await fetchEvents(
                for: account,
                token: token,
                since: request.since,
                until: request.until
            )
            items.append(contentsOf: raw)
        }
        return items
    }

    /// Issues one `events.list` request for `account` and stashes each returned event.
    private func fetchEvents(
        for account: Account,
        token: String,
        since: Date,
        until: Date
    ) async throws -> [RawItem] {
        let urlRequest = Self.makeEventsRequest(
            calendarId: Self.calendarId,
            token: token,
            timeMin: since,
            timeMax: until,
            timeZone: timeZone
        )

        let data: Data
        do {
            (data, _) = try await transport.send(urlRequest)
        } catch let error as TransportError {
            throw GoogleCalendarConnector.mapTransportError(error)
        } catch is CancellationError {
            throw ConnectorError.timedOut
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw ConnectorError.timedOut
        } catch {
            throw ConnectorError.network(statusCode: nil, reason: "request failed")
        }

        let json: JSONValue
        do {
            json = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ConnectorError.decodingFailed(reason: "events.list response was not valid JSON")
        }

        guard let events = json["items"]?.array else {
            // A well-formed response with no events is empty, not an error.
            return []
        }

        return events.enumerated().compactMap { index, event in
            // Google events always carry an id; fall back to a positional id only as a guard.
            let eventId = event["id"]?.string ?? "\(account.label)#\(index)"
            return RawItem(
                id: eventId,
                connectorId: Self.id,
                accountLabel: account.label,
                json: event
            )
        }
    }

    /// Builds the `events.list` `URLRequest` for one calendar (kept `static` for direct test access).
    static func makeEventsRequest(
        calendarId: String,
        token: String,
        timeMin: Date,
        timeMax: Date,
        timeZone: TimeZone
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        // calendarId is path-encoded; "primary" needs no escaping but a real id may.
        let encodedCalendar = calendarId
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        components.path = "/calendar/v3/calendars/\(encodedCalendar)/events"
        // Percent-encode the values OURSELVES (via `percentEncodedQueryItems`), because
        // `URLComponents.queryItems` does NOT encode "+". The RFC3339 timezone offset for
        // a positive zone (e.g. "+07:00") would then be sent literally, and a server
        // decodes "+" in a query as a space → "2026-06-18T00:00:00 07:00" → HTTP 400.
        // Escaping "+" to "%2B" makes Google receive the correct timestamp.
        let valueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+"))
        func encoded(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? value
        }
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: encoded(RFC3339.string(from: timeMin, timeZone: timeZone))),
            URLQueryItem(name: "timeMax", value: encoded(RFC3339.string(from: timeMax, timeZone: timeZone))),
            URLQueryItem(name: "maxResults", value: "250"),
            // No `fields` projection: it's only a payload optimization, and a malformed
            // field mask is another common cause of HTTP 400 from events.list. The
            // normalizer reads only the fields it needs from the full response.
        ]

        // URLComponents builds a safe absolute URL from validated parts.
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        return urlRequest
    }

    /// Maps a transport-level error to the connector's typed error surface.
    static func mapTransportError(_ error: TransportError) -> ConnectorError {
        switch error {
        case .nonHTTPResponse:
            return .network(statusCode: nil, reason: "non-HTTP response")
        case let .unacceptableStatus(code, body):
            switch code {
            case 401, 403:
                return .authFailed(reason: "calendar access was denied (HTTP \(code))")
            default:
                // Keep a snippet of Google's error body — for a 4xx it's the API's own
                // error JSON (no user data), which names the rejected param/field.
                let snippet = String(decoding: body.prefix(400), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = snippet.isEmpty ? "" : ": \(snippet)"
                return .network(statusCode: code, reason: "events.list returned HTTP \(code)\(detail)")
            }
        }
    }

    // MARK: - Normalize

    public func normalize(_ raw: [RawItem]) -> [BriefItem] {
        let now = dateProvider.now()
        return raw.compactMap { item in
            Self.normalizeEvent(item, now: now, fallbackTimeZone: timeZone)
        }
    }

    /// Maps a single raw event into a ``BriefItem``, or `nil` if it should be dropped
    /// (cancelled instance, or no usable start time).
    private static func normalizeEvent(_ item: RawItem, now: Date, fallbackTimeZone: TimeZone) -> BriefItem? {
        let event = item.json

        // Skip cancelled instances — they still appear in events.list with singleEvents=true.
        if event["status"]?.string == "cancelled" { return nil }

        guard let start = EventStart(from: event["start"], fallbackTimeZone: fallbackTimeZone) else { return nil }

        let title = event["summary"]?.string ?? "(no title)"
        let body = Self.bodyText(from: event)
        let people = Self.attendeeNames(from: event["attendees"])
        let url = (event["htmlLink"]?.string).flatMap(URL.init(string:))
        let urgencyHints = Self.urgencyHints(for: event, start: start, now: now)

        return BriefItem(
            source: .gcal,
            // The account label is the connector's account identity; space is assigned by the
            // pipeline from the Account, so connectors emit a neutral default here.
            account: item.accountLabel,
            space: "",
            type: .event,
            title: title,
            body: body,
            people: people,
            timestamp: start.date,
            url: url,
            urgencyHints: urgencyHints
        )
    }

    /// Joins location and description into a single body string (either may be absent).
    private static func bodyText(from event: JSONValue) -> String? {
        let location = event["location"]?.string
        let description = event["description"]?.string
        let parts = [location, description].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Extracts attendee display names (falling back to email) from the `attendees` array.
    private static func attendeeNames(from attendees: JSONValue?) -> [String] {
        guard let list = attendees?.array else { return [] }
        return list.compactMap { attendee in
            if let name = attendee["displayName"]?.string, !name.isEmpty { return name }
            if let email = attendee["email"]?.string, !email.isEmpty { return email }
            return nil
        }
    }

    /// Builds the event's urgency hints additively (research §"BriefItem normalization").
    ///
    /// Hints are independent signals and accumulate rather than replace each other:
    /// - `.scheduledToday` — the event falls on "today" (judged in the event's own zone).
    /// - `.other("all_day")` — an all-day event (`start.date`, no time).
    /// - `.other("needs_response")` — the reader (the `self` attendee) hasn't replied
    ///   (`responseStatus == "needsAction"`).
    /// - `.other("has_video")` — a video conference is attached (`hangoutLink`, or a
    ///   `conferenceData` entry point of type `video`).
    ///
    /// Order is deterministic (scheduledToday → all_day → needs_response → has_video) so
    /// snapshots and assertions are stable.
    static func urgencyHints(for event: JSONValue, start: EventStart, now: Date) -> [UrgencyHint] {
        var hints: [UrgencyHint] = []
        if start.isOnSameDay(as: now) { hints.append(.scheduledToday) }
        if start.isAllDay { hints.append(.other("all_day")) }
        if selfNeedsResponse(in: event) { hints.append(.other("needs_response")) }
        if hasVideo(in: event) { hints.append(.other("has_video")) }
        return hints
    }

    /// Whether the reader (the attendee flagged `self: true`) still owes a response,
    /// i.e. their `responseStatus` is `"needsAction"`. Absent a `self` attendee (e.g. the
    /// reader is the organizer with no attendee row), there is nothing to respond to.
    private static func selfNeedsResponse(in event: JSONValue) -> Bool {
        guard let attendees = event["attendees"]?.array else { return false }
        guard let selfAttendee = attendees.first(where: { $0["self"]?.bool == true }) else { return false }
        return selfAttendee["responseStatus"]?.string == "needsAction"
    }

    /// Whether a video conference is attached: either the legacy `hangoutLink`, or a
    /// `conferenceData.entryPoints` entry whose `entryPointType` is `"video"`.
    private static func hasVideo(in event: JSONValue) -> Bool {
        if let link = event["hangoutLink"]?.string, !link.isEmpty { return true }
        guard let entryPoints = event["conferenceData"]?["entryPoints"]?.array else { return false }
        return entryPoints.contains { $0["entryPointType"]?.string == "video" }
    }
}
