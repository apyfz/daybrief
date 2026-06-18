import ConnectorKit
import CryptoKit
import DaybriefCore
import Foundation
import os

/// Reads a user's Slack **mentions** and **direct messages** over the brief window.
///
/// ## Auth
/// Uses ``AuthStrategy/pastedUserToken(_:)``: the user creates their own *internal*
/// Slack app (single workspace, public distribution never activated), installs it, and
/// pastes the **User OAuth token** (`xoxp-`). The token is supplied per account by the
/// injected ``TokenProvider``. A user token is mandatory — `search.messages` (the only
/// way to read mentions across channels) requires the user-only `search:read` scope;
/// bot tokens (`xoxb-`) cannot search at all.
///
/// ## Fetch
/// Per account:
/// 1. **Identity** — `GET auth.test` resolves the authed user's `user_id` (and handle)
///    so mentions can be narrowed to *this* user and honestly labeled.
/// 2. **Mentions** — `GET search.messages?query=after:<since> @<handle>` (Tier-2,
///    user-token-only), then a second pass keeps only matches whose text actually
///    contains the `<@user_id>` mention token — `search.messages` matches text
///    fuzzily, so the bare query alone surfaces non-mentions too.
/// 3. **DMs** — `GET conversations.list?types=im,mpim` then, for each DM channel,
///    `GET conversations.info?channel=<id>` to read the per-user
///    `unread_count_display`; channels with nothing unread are skipped, and for the
///    rest the `unread` most-recent messages are pulled with
///    `GET conversations.history?limit=<unread>&inclusive=true` (newest-first, so the
///    unread tail is returned regardless of age — a genuinely-unread DM from days ago
///    still surfaces).
///
/// If `auth.test` can't resolve the user's identity, the mentions search is skipped
/// entirely (DMs are still returned) rather than mislabeling every visible message as
/// a mention.
///
/// Each Slack message is stashed verbatim into a ``RawItem`` (wrapped in a small
/// envelope recording its origin and channel) for ``normalize(_:)`` to interpret.
///
/// ## Rate limits
/// An *internal* app keeps Tier-3 limits, so a 24h sweep is a handful of calls. If
/// Slack returns `429`/`ratelimited`, the connector surfaces a clear
/// "set your app back to internal" hint (a distributed app is the usual cause) — see
/// ``SlackResponse/distributedAppHint``.
///
/// Resolving user ids to display names is out of scope for v0.
public struct SlackConnector: Connector {
    public static let id: ConnectorID = .slack
    public static let displayName = "Slack"

    /// Maximum DM/MPIM channels swept per account in one fetch (keeps a single brief
    /// well inside the Tier-3 budget even for very chatty workspaces).
    private static let maxDMChannels = 30
    /// Upper bound on messages pulled per DM channel: a DM's history request asks for
    /// `min(unread, historyLimit)` so a single very stale, high-unread channel can't
    /// blow the page budget (Tier-3 honors up to 1000).
    private static let historyLimit = 200

    /// Message subtypes that are pure channel/system events (joins, renames, pins, …) and
    /// carry nothing worth briefing. Everything else — including **bot/app messages, file
    /// shares, and `/me`** — is kept. The previous "drop any subtype" rule silently nuked
    /// unread bot/app and file DMs, so Slack surfaced nothing even when there was unread.
    private static let noiseSubtypes: Set<String> = [
        "channel_join", "channel_leave", "channel_topic", "channel_purpose", "channel_name",
        "channel_archive", "channel_unarchive",
        "group_join", "group_leave", "group_topic", "group_purpose", "group_name",
        "group_archive", "group_unarchive",
        "pinned_item", "unpinned_item",
    ]

    private static let logger = Logger(subsystem: "co.daybrief.connector", category: "slack")

    private let transport: any HTTPTransport
    private let tokenProvider: any TokenProvider

    public let auth: AuthStrategy = .pastedUserToken(SlackSetup.tokenSpec)
    public let fetchTimeout: Duration

    /// Creates a Slack connector.
    ///
    /// - Parameters:
    ///   - transport: HTTP seam (defaults to ``URLSessionHTTPTransport``); inject
    ///     ``MockHTTPTransport`` in tests.
    ///   - tokenProvider: Resolves the stored `xoxp-` user token per account.
    ///   - fetchTimeout: The orchestrator's per-connector budget (default 20s).
    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        tokenProvider: any TokenProvider,
        fetchTimeout: Duration = .seconds(20)
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.fetchTimeout = fetchTimeout
    }

    // MARK: - Fetch

    public func fetch(_ request: FetchRequest) async throws -> [RawItem] {
        var items: [RawItem] = []
        for account in request.accounts {
            try Task.checkCancellation()
            let token = try await tokenProvider.accessToken(for: account)
            // Resolve who the token belongs to so mentions can be narrowed to — and
            // honestly verified against — this user. If identity can't be resolved we
            // skip the mentions search rather than mislabel everything (DMs still run).
            let identity = try await resolveSelf(token: token)
            if let identity {
                items += try await fetchMentions(
                    token: token,
                    account: account,
                    since: request.since,
                    identity: identity
                )
            } else {
                Self.logger.warning(
                    "auth.test did not return a user_id; skipping the Slack mentions search and returning DMs only."
                )
            }
            items += try await fetchDMs(token: token, account: account)
        }
        return items
    }

    /// The authed user's identity, resolved from `auth.test`.
    struct SelfIdentity: Equatable {
        /// The user's Slack id (e.g. `U01ALIM`). Used to build the `<@id>` mention token.
        let userID: String
        /// The user's handle (e.g. `alim`), if Slack returned one. Used as a search term.
        let handle: String?

        /// The canonical encoding of an @-mention of this user inside Slack message text.
        var mentionToken: String {
            "<@\(userID)>"
        }
    }

    /// Resolves the token holder's identity via `auth.test`.
    ///
    /// `auth.test` returns `user_id` (always) and `user` (the handle) for the user the
    /// token belongs to. Returns `nil` if no `user_id` is present so the caller can
    /// degrade gracefully instead of mislabeling messages.
    private func resolveSelf(token: String) async throws -> SelfIdentity? {
        let components = Self.apiComponents(method: "auth.test")
        let json = try await get(components, token: token, method: "auth.test")
        guard let userID = json["user_id"]?.string, !userID.isEmpty else { return nil }
        let handle = json["user"]?.string
        return SelfIdentity(userID: userID, handle: handle.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Mentions via `search.messages` over the window, narrowed to the authed user.
    ///
    /// The query is `after:<day-before-since>` (date-granular, so anchored on the day
    /// before `since` to include `since` itself) **plus the user's `@handle`** when one
    /// is known, which steers Slack search toward messages that name the user. Because
    /// `search.messages` matches text fuzzily — the bare `@handle` term can return
    /// messages that merely contain the word, not a real mention — every match is then
    /// re-checked against the `<@user_id>` mention token and only true mentions are kept
    /// and labeled ``SlackRawEnvelope/Origin/mention``.
    private func fetchMentions(
        token: String,
        account: Account,
        since: Date,
        identity: SelfIdentity
    ) async throws -> [RawItem] {
        // Slack's `after:` filter is date-granular (YYYY-MM-DD) and exclusive of the
        // named day, so anchor it on the day before `since` to include `since` itself.
        let afterDay = Self.searchDay(forDayBefore: since)
        var query = "after:\(afterDay)"
        if let handle = identity.handle {
            query += " @\(handle)"
        }
        var components = Self.apiComponents(method: "search.messages")
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "count", value: "100"),
            URLQueryItem(name: "sort", value: "timestamp"),
        ]
        let json = try await get(components, token: token, method: "search.messages")

        guard let matches = json["messages"]?["matches"]?.array else { return [] }
        return matches.compactMap { match in
            guard let ts = match["ts"]?.string else { return nil }
            // Only label a match as a mention if its text actually names the user;
            // fuzzy search hits that merely contain the handle as a word are dropped.
            guard let text = match["text"]?.string,
                  text.contains(identity.mentionToken)
            else { return nil }
            let envelope = SlackRawEnvelope(
                origin: .mention,
                channelName: match["channel"]?["name"]?.string,
                message: match
            )
            return RawItem(
                id: "mention:\(ts)",
                connectorId: Self.id,
                accountLabel: account.label,
                json: envelope.json
            )
        }
    }

    /// Unread DMs + group-DMs via `conversations.list`, then per channel a
    /// `conversations.info` read of the unread count and, when non-zero, a
    /// `conversations.history` pull of exactly that many newest messages.
    ///
    /// This is **unread-based, not window-based**: `conversations.info`'s per-user
    /// `unread_count_display` tells us how many messages the user hasn't read, and
    /// `conversations.history` returns newest-first, so the `unread` most-recent
    /// messages *are* the unread ones — regardless of how old they are. A DM that
    /// went unread for days still surfaces; a fully-read channel is skipped with no
    /// history call. (`unread_count_display` requires the `im:read`/`mpim:read`
    /// scopes the connector already documents.)
    private func fetchDMs(token: String, account: Account) async throws -> [RawItem] {
        var listComponents = Self.apiComponents(method: "conversations.list")
        listComponents.queryItems = [
            URLQueryItem(name: "types", value: "im,mpim"),
            URLQueryItem(name: "exclude_archived", value: "true"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        let listJSON = try await get(listComponents, token: token, method: "conversations.list")
        let channels = (listJSON["channels"]?.array ?? []).prefix(Self.maxDMChannels)

        var items: [RawItem] = []
        for channel in channels {
            try Task.checkCancellation()
            guard let channelID = channel["id"]?.string else { continue }

            // Per-user unread count for this DM. `conversations.list` doesn't carry it,
            // so ask `conversations.info` (which returns the authed user's view).
            var infoComponents = Self.apiComponents(method: "conversations.info")
            infoComponents.queryItems = [
                URLQueryItem(name: "channel", value: channelID),
            ]
            let infoJSON = try await get(infoComponents, token: token, method: "conversations.info")
            let unread = infoJSON["channel"]?["unread_count_display"]?.int ?? 0
            // Nothing unread → don't spend a history call; this channel contributes nothing.
            guard unread > 0 else { continue }

            // Pull only the unread tail. Slack returns newest-first with no oldest/latest,
            // so the `unread` most-recent messages are exactly the unread ones (capped at
            // the page size as a safety bound for very stale, high-count channels).
            let limit = min(unread, Self.historyLimit)
            var historyComponents = Self.apiComponents(method: "conversations.history")
            historyComponents.queryItems = [
                URLQueryItem(name: "channel", value: channelID),
                URLQueryItem(name: "inclusive", value: "true"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
            let historyJSON = try await get(historyComponents, token: token, method: "conversations.history")
            let messages = historyJSON["messages"]?.array ?? []

            let isGroup = channel["is_mpim"]?.bool == true
            for message in messages {
                guard let ts = message["ts"]?.string else { continue }
                // Skip only true system events (joins/renames/pins). Content-bearing
                // subtypes — bot/app DMs, file shares, /me — are kept, so unread bot/file
                // DMs surface instead of silently vanishing.
                if let subtype = message["subtype"]?.string, Self.noiseSubtypes.contains(subtype) { continue }
                let envelope = SlackRawEnvelope(
                    origin: isGroup ? .groupDM : .directMessage,
                    channelName: channel["name"]?.string ?? channelID,
                    message: message
                )
                items.append(RawItem(
                    id: "dm:\(channelID):\(ts)",
                    connectorId: Self.id,
                    accountLabel: account.label,
                    json: envelope.json
                ))
            }
        }
        return items
    }

    /// Issues a GET with `Authorization: Bearer <token>` and verifies the Slack envelope.
    ///
    /// `URLSessionHTTPTransport` throws ``TransportError/unacceptableStatus(code:body:)``
    /// on a non-2xx status; we translate a `429` into the distributed-app hint and any
    /// other non-2xx into a ``ConnectorError/network(statusCode:reason:)``. On a 200 we
    /// still inspect the body's `ok` flag (Slack reports failures with HTTP 200).
    private func get(_ components: URLComponents, token: String, method: String) async throws -> JSONValue {
        guard let url = components.url else {
            throw ConnectorError.other(reason: "\(method): could not build request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let TransportError.unacceptableStatus(code, _) {
            if code == 429 {
                throw ConnectorError.network(statusCode: 429, reason: SlackResponse.distributedAppHint)
            }
            throw ConnectorError.network(statusCode: code, reason: "\(method) returned HTTP \(code)")
        } catch let error as ConnectorError {
            throw error
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ConnectorError.network(statusCode: nil, reason: "\(method) request failed")
        }
        return try SlackResponse.decodeOK(data, method: method)
    }

    // MARK: - Normalize

    public func normalize(_ raw: [RawItem]) -> [BriefItem] {
        raw.compactMap { item -> BriefItem? in
            guard let envelope = SlackRawEnvelope(json: item.json) else { return nil }
            let message = envelope.message

            guard let ts = message["ts"]?.string, let timestamp = Self.date(fromSlackTS: ts) else {
                return nil
            }
            let text = message["text"]?.string ?? ""
            // v0: user ids aren't resolved to names — prefer the search `username`,
            // else fall back to the raw user id. // TODO users.info to resolve names.
            let sender = message["username"]?.string ?? message["user"]?.string ?? "unknown"

            let location: String
            switch envelope.origin {
            case .mention:
                location = envelope.channelName.map { "#\($0)" } ?? "a channel"
            case .directMessage:
                location = "DM"
            case .groupDM:
                location = envelope.channelName.map { "group DM \($0)" } ?? "a group DM"
            }

            let hints: [UrgencyHint] = (envelope.origin == .mention) ? [.mention] : [.unread]

            return BriefItem(
                id: Self.itemUUID(for: item.id),
                source: Self.id,
                account: item.accountLabel,
                // A connector can't know the Space (a per-Account tag) — the orchestrator
                // stamps it from the originating Account after normalize.
                space: "",
                type: .message,
                title: Self.summaryTitle(sender: sender, location: location, origin: envelope.origin),
                body: text.isEmpty ? nil : text,
                people: [sender],
                timestamp: timestamp,
                url: message["permalink"]?.string.flatMap(URL.init(string:)),
                urgencyHints: hints
            )
        }
    }

    // MARK: - Helpers

    /// Base `URLComponents` for a Slack Web API `method`, built field-by-field so there's
    /// no force-unwrap of a string-parsed URL.
    private static func apiComponents(method: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "slack.com"
        components.path = "/api/\(method)"
        return components
    }

    /// A short, channel/DM + sender headline for the brief.
    private static func summaryTitle(sender: String, location: String, origin: SlackRawEnvelope.Origin) -> String {
        switch origin {
        case .mention:
            return "\(sender) mentioned you in \(location)"
        case .directMessage:
            return "Direct message from \(sender)"
        case .groupDM:
            return "\(sender) in \(location)"
        }
    }

    /// Slack `ts` is epoch seconds with a fractional microsecond part ("1750118400.001500").
    static func date(fromSlackTS ts: String) -> Date? {
        guard let seconds = Double(ts) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// `YYYY-MM-DD` (UTC) for the day before `date`, for `search.messages`'
    /// day-granular, exclusive `after:` filter.
    static func searchDay(forDayBefore date: Date) -> String {
        let dayBefore = date.addingTimeInterval(-86400)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: dayBefore)
    }

    /// A stable `UUID` derived from the Slack item id so the same message normalizes to
    /// the same `BriefItem.id` across fetches (deduplication-friendly, deterministic in tests).
    static func itemUUID(for rawID: String) -> UUID {
        let digest = SHA256.hash(data: Data(rawID.utf8))
        var bytes = Array(digest.prefix(16))
        // Stamp RFC-4122 version (5) and variant bits so it's a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
