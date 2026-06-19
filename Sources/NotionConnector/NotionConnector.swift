import ConnectorKit
import CryptoKit
import DaybriefCore
import Foundation
import os

/// Reads a user's **Notion tasks that are due today or overdue and not yet done**.
///
/// ## Auth
/// Uses ``AuthStrategy/pastedUserToken(_:)``: the user creates their own *internal*
/// integration at notion.so/my-integrations, shares the databases they care about with
/// it, and pastes the integration secret (`ntn_…` or `secret_…`). The token is supplied
/// per account by the injected ``TokenProvider``.
///
/// ## Config-free by design
/// Notion databases are freeform — property names ("Due", "Status", "Assignee") vary per
/// workspace — so rather than make the user pick a database and map its columns, the
/// connector **auto-discovers** the task-shaped databases the integration can see. The
/// user controls scope simply by which databases they share with the integration.
///
/// ## Fetch
/// Per account:
/// 1. **Identity** — `GET /v1/users/me` resolves the integration's owner (the human who
///    created it, when the integration is user-owned) so tasks can be narrowed to "mine".
/// 2. **Discover** — `POST /v1/search` lists the databases shared with the integration.
/// 3. **Per database** — a database is treated as *tasks* only if it has both a `date`
///    property (the due date) and a `checkbox`/`status` property (done state). For each,
///    `POST /v1/databases/{id}/query` pulls items **due on or before today**, then the
///    connector drops anything already **done** and anything explicitly **assigned to
///    someone else** (unassigned and assigned-to-me tasks are kept).
///
/// Each surviving task is extracted into a small ``NotionRawEnvelope`` (schema-independent)
/// for ``normalize(_:)``.
///
/// ## Rate limits
/// Notion allows ~3 requests/second; a once-a-day sweep over a handful of databases is
/// well within budget. Pagination is single-page per call (v1) — ample for a day's tasks.
public struct NotionConnector: Connector {
    public static let id: ConnectorID = .notion
    public static let displayName = "Notion"

    /// The Notion API version this connector targets. Pinned to the stable
    /// `databases.query` era (the newer "data source" split is deliberately avoided).
    private static let apiVersion = "2022-06-28"

    /// Maximum databases swept per account in one fetch (keeps a single brief light).
    private static let maxDatabases = 25
    /// Page size for search + query calls.
    private static let pageSize = 100

    /// Status option names treated as "done" when a database has no explicit
    /// "Complete"-group (a fallback for plain select/status columns).
    private static let doneStatusFallback: Set<String> = [
        "done", "complete", "completed", "closed", "archived", "shipped", "cancelled", "canceled",
    ]

    private static let logger = Logger(subsystem: "co.daybrief.connector", category: "notion")

    private let transport: any HTTPTransport
    private let tokenProvider: any TokenProvider

    public let auth: AuthStrategy = .pastedUserToken(NotionSetup.tokenSpec)
    public let fetchTimeout: Duration

    /// Creates a Notion connector.
    ///
    /// - Parameters:
    ///   - transport: HTTP seam (defaults to ``URLSessionHTTPTransport``); inject
    ///     ``MockHTTPTransport`` in tests.
    ///   - tokenProvider: Resolves the stored integration secret per account.
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
            // Who owns the integration (the human), so tasks can be narrowed to "mine".
            // Best-effort: when the integration is workspace-owned this is nil and the
            // assignee filter simply doesn't exclude anyone.
            let meUserID = try? await resolveOwnerUserID(token: token)
            let databases = try await searchDatabases(token: token)
            for database in databases.prefix(Self.maxDatabases) {
                try Task.checkCancellation()
                items += try await fetchTasks(
                    in: database, token: token, account: account, request: request, meUserID: meUserID
                )
            }
        }
        return items
    }

    /// The integration owner's user id, from `GET /v1/users/me`'s `bot.owner.user.id`.
    /// `nil` when the integration is workspace-owned (no single human owner).
    private func resolveOwnerUserID(token: String) async throws -> String? {
        let json = try await get(path: "/v1/users/me", token: token, context: "users/me")
        return json["bot"]?["owner"]?["user"]?["id"]?.string
    }

    /// Databases the integration can see, via `POST /v1/search` filtered to databases.
    private func searchDatabases(token: String) async throws -> [JSONValue] {
        let body: JSONValue = .object([
            "filter": .object(["value": .string("database"), "property": .string("object")]),
            "page_size": .number(Double(Self.pageSize)),
        ])
        let json = try await post(path: "/v1/search", body: body, token: token, context: "search")
        return json["results"]?.array ?? []
    }

    /// Pulls due/overdue, not-done, mine-or-unassigned tasks from one database.
    private func fetchTasks(
        in database: JSONValue,
        token: String,
        account: Account,
        request: FetchRequest,
        meUserID: String?
    ) async throws -> [RawItem] {
        let properties = database["properties"]?.object ?? [:]
        // A database is "tasks" only if it has a due date AND a done state.
        guard let dueName = Self.detectProperty(in: properties, types: ["date"],
                                                preferNames: ["due", "deadline", "date", "do date"]),
              let done = Self.detectDoneProperty(in: properties)
        else { return [] }

        let titleName = Self.detectProperty(in: properties, types: ["title"], preferNames: [])
        let peopleName = Self.detectProperty(in: properties, types: ["people"],
                                             preferNames: ["assignee", "owner", "assigned", "person"])
        let databaseTitle = Self.plainText(database["title"])
        let todayStart = Calendar.current.startOfDay(for: request.until)

        let body: JSONValue = .object([
            "filter": .object([
                "property": .string(dueName),
                "date": .object(["on_or_before": .string(Self.dayString(from: request.until))]),
            ]),
            "sorts": .array([.object([
                "property": .string(dueName), "direction": .string("ascending"),
            ])]),
            "page_size": .number(Double(Self.pageSize)),
        ])
        guard let databaseID = database["id"]?.string else { return [] }
        let json = try await post(
            path: "/v1/databases/\(databaseID)/query", body: body, token: token,
            context: "databases.query"
        )
        let pages = json["results"]?.array ?? []

        return pages.compactMap { page -> RawItem? in
            guard let pageID = page["id"]?.string else { return nil }
            let pageProps = page["properties"]?.object ?? [:]

            // Done → skip; you don't need to be reminded of finished work.
            if Self.isDone(pageProps[done.name], type: done.type, doneStatusNames: done.doneNames) {
                return nil
            }
            // Assigned to someone else → skip. Unassigned or assigned-to-me is kept, so a
            // solo workspace (no assignees) still surfaces everything.
            if let meUserID, let peopleName {
                let assigneeIDs = Self.peopleIDs(pageProps[peopleName])
                if !assigneeIDs.isEmpty, !assigneeIDs.contains(meUserID) { return nil }
            }

            let dueISO = pageProps[dueName]?["date"]?["start"]?.string
            let isOverdue = dueISO.flatMap(Self.parseDate).map { $0 < todayStart } ?? false
            let title = Self.title(in: pageProps, titleName: titleName)
            let assignees = peopleName.map { Self.peopleNames(pageProps[$0]) } ?? []

            let envelope = NotionRawEnvelope(
                pageId: pageID,
                title: title.isEmpty ? "Untitled task" : title,
                databaseTitle: databaseTitle,
                dueISO: dueISO,
                assignees: assignees,
                url: page["url"]?.string,
                isOverdue: isOverdue
            )
            return RawItem(
                id: "task:\(pageID)", connectorId: Self.id, accountLabel: account.label, json: envelope.json
            )
        }
    }

    // MARK: - Normalize

    public func normalize(_ raw: [RawItem]) -> [BriefItem] {
        raw.compactMap { item -> BriefItem? in
            guard let envelope = NotionRawEnvelope(json: item.json) else { return nil }
            // Tasks are filtered to a due date during fetch; fall back to the item's own
            // time only if a malformed envelope slipped through.
            let timestamp = envelope.dueISO.flatMap(Self.parseDate) ?? Date(timeIntervalSince1970: 0)

            return BriefItem(
                id: Self.itemUUID(for: item.id),
                source: Self.id,
                account: item.accountLabel,
                // The orchestrator stamps the Space from the originating Account post-normalize.
                space: "",
                type: .unknown("task"),
                title: envelope.title,
                body: envelope.databaseTitle.isEmpty ? nil : "From \(envelope.databaseTitle)",
                people: envelope.assignees,
                timestamp: timestamp,
                url: envelope.url.flatMap(URL.init(string:)),
                urgencyHints: envelope.isOverdue ? [.other("overdue")] : [.dueToday]
            )
        }
    }

    // MARK: - HTTP

    private func get(path: String, token: String, context: String) async throws -> JSONValue {
        try await send(method: "GET", path: path, body: nil, token: token, context: context)
    }

    private func post(path: String, body: JSONValue, token: String, context: String) async throws -> JSONValue {
        let data = try JSONEncoder().encode(body)
        return try await send(method: "POST", path: path, body: data, token: token, context: context)
    }

    /// Issues a request with the Notion auth + version headers and maps failures to
    /// typed ``ConnectorError``s (the transport throws on non-2xx).
    private func send(method: String, path: String, body: Data?, token: String, context: String) async throws -> JSONValue {
        guard let url = URL(string: "https://api.notion.com\(path)") else {
            throw ConnectorError.other(reason: "\(context): could not build request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let TransportError.unacceptableStatus(code, errorBody) {
            throw NotionResponse.error(statusCode: code, body: errorBody, context: context)
        } catch let error as ConnectorError {
            throw error
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ConnectorError.network(statusCode: nil, reason: "\(context) request failed")
        }
        return try NotionResponse.decode(data, context: context)
    }

    // MARK: - Property detection

    /// The done-state property: its name, type (`checkbox`/`status`/`select`), and — for
    /// status/select — the set of option names that mean "done".
    struct DoneProperty {
        let name: String
        /// `"checkbox"`, `"status"`, or `"select"`.
        let type: String
        /// Option names that count as done (status/select only; empty for checkbox).
        let doneNames: Set<String>
    }

    /// The first property matching one of `types`, preferring names that contain one of
    /// `preferNames` (case-insensitive); deterministic by falling back to the
    /// alphabetically-first match (a dictionary has no stable order).
    static func detectProperty(in properties: [String: JSONValue], types: Set<String>, preferNames: [String]) -> String? {
        let matches = properties
            .filter { types.contains($0.value["type"]?.string ?? "") }
            .map(\.key)
        guard !matches.isEmpty else { return nil }
        for prefer in preferNames {
            if let hit = matches.sorted().first(where: { $0.lowercased().contains(prefer) }) {
                return hit
            }
        }
        return matches.sorted().first
    }

    static func detectProperty(in properties: [String: JSONValue], types: [String], preferNames: [String]) -> String? {
        detectProperty(in: properties, types: Set(types), preferNames: preferNames)
    }

    /// Detects the done-state property, preferring a `checkbox`, then a `status`, then a
    /// `select`. For status/select, derives the "done" option names from the column's
    /// "Complete" group when present, else a name heuristic.
    static func detectDoneProperty(in properties: [String: JSONValue]) -> DoneProperty? {
        if let checkbox = detectProperty(in: properties, types: ["checkbox"], preferNames: ["done", "complete"]) {
            return DoneProperty(name: checkbox, type: "checkbox", doneNames: [])
        }
        for type in ["status", "select"] {
            if let name = detectProperty(in: properties, types: [type], preferNames: ["status", "state"]) {
                return DoneProperty(name: name, type: type, doneNames: doneOptionNames(properties[name], type: type))
            }
        }
        return nil
    }

    /// The set of option names that mean "done" for a status/select schema property:
    /// the options in any group whose name reads as complete/done, else a name heuristic
    /// over all options.
    private static func doneOptionNames(_ property: JSONValue?, type: String) -> Set<String> {
        let detail = property?[type]
        let options = detail?["options"]?.array ?? []
        let idToName: [String: String] = options.reduce(into: [:]) { map, option in
            if let id = option["id"]?.string, let name = option["name"]?.string { map[id] = name }
        }
        // Status columns group options (To-do / In progress / Complete). Prefer the
        // "complete"-named group's options.
        let groups = detail?["groups"]?.array ?? []
        var names = Set<String>()
        for group in groups {
            let groupName = (group["name"]?.string ?? "").lowercased()
            guard groupName.contains("complete") || groupName.contains("done") else { continue }
            for idValue in group["option_ids"]?.array ?? [] {
                if let id = idValue.string, let name = idToName[id] { names.insert(name.lowercased()) }
            }
        }
        if !names.isEmpty { return names }
        // No usable group → fall back to option names that look done.
        return Set(idToName.values.map { $0.lowercased() }.filter { doneStatusFallback.contains($0) })
    }

    // MARK: - Page value extraction

    /// Whether a page's done property marks it complete.
    static func isDone(_ value: JSONValue?, type: String, doneStatusNames: Set<String>) -> Bool {
        switch type {
        case "checkbox":
            return value?["checkbox"]?.bool == true
        case "status":
            let name = value?["status"]?["name"]?.string?.lowercased() ?? ""
            return doneStatusNames.contains(name) || (doneStatusNames.isEmpty && doneStatusFallback.contains(name))
        case "select":
            let name = value?["select"]?["name"]?.string?.lowercased() ?? ""
            return doneStatusNames.contains(name) || (doneStatusNames.isEmpty && doneStatusFallback.contains(name))
        default:
            return false
        }
    }

    /// The page's title as plain text: the `title`-type property, found by name or by scan.
    static func title(in properties: [String: JSONValue], titleName: String?) -> String {
        if let titleName, let value = properties[titleName] {
            return plainText(value["title"])
        }
        // Fall back to scanning for the title-typed property.
        if let value = properties.values.first(where: { $0["type"]?.string == "title" }) {
            return plainText(value["title"])
        }
        return ""
    }

    /// Joins a Notion rich-text / title array into plain text.
    static func plainText(_ richText: JSONValue?) -> String {
        (richText?.array ?? [])
            .compactMap { $0["plain_text"]?.string }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Display names of a `people` property's members.
    static func peopleNames(_ value: JSONValue?) -> [String] {
        (value?["people"]?.array ?? []).compactMap { $0["name"]?.string }
    }

    /// User ids of a `people` property's members (for the assignee filter).
    static func peopleIDs(_ value: JSONValue?) -> [String] {
        (value?["people"]?.array ?? []).compactMap { $0["id"]?.string }
    }

    // MARK: - Date helpers

    /// `YYYY-MM-DD` (local day) for Notion's day-granular `on_or_before` filter.
    static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Parses a Notion date string (date-only or full datetime) into a `Date`.
    ///
    /// `ISO8601DateFormatter` isn't `Sendable`, so the datetime parsers are built locally
    /// per call (cheap — a brief has a handful of tasks) rather than shared statically.
    static func parseDate(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: iso) { return date }
        return dayFormatter.date(from: iso)
    }

    /// `DateFormatter` is `Sendable` on this SDK, so the day formatter — configured once
    /// and only ever read — is shared safely.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A stable `UUID` derived from the item id so the same task normalizes to the same
    /// `BriefItem.id` across fetches (dedup-friendly, deterministic in tests). Mirrors
    /// the Slack connector's scheme.
    static func itemUUID(for rawID: String) -> UUID {
        let digest = SHA256.hash(data: Data(rawID.utf8))
        var bytes = Array(digest.prefix(16))
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
