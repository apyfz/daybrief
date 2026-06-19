import DaybriefCore
import Foundation

/// The shape stashed into ``RawItem/json`` by ``NotionConnector/fetch(_:)``.
///
/// A Notion task page's fields live in arbitrarily-named properties whose meaning is
/// only knowable from the parent database's schema (which property is the due date,
/// which is the title, which is the assignee). `fetch` has that schema, `normalize`
/// does not — so rather than stash the raw page and re-derive the schema in
/// `normalize`, fetch extracts the few fields the brief needs into this small,
/// schema-independent envelope. Everything round-trips through a plain ``JSONValue``
/// (fixture- and XPC-safe), mirroring ``SlackRawEnvelope``.
struct NotionRawEnvelope {
    /// The task page's stable id.
    let pageId: String
    /// The task's title (the page's title property as plain text).
    let title: String
    /// The parent database's title, used as light context ("From <project>").
    let databaseTitle: String
    /// The due date as an ISO-8601 string (the date property's `start`), if any.
    let dueISO: String?
    /// Display names of the people assigned to the task.
    let assignees: [String]
    /// The page's deep link.
    let url: String?
    /// Whether the due date is before the brief window (so normalize can flag it overdue).
    let isOverdue: Bool

    /// The envelope encoded as a ``JSONValue`` for ``RawItem/json``.
    var json: JSONValue {
        var object: [String: JSONValue] = [
            "pageId": .string(pageId),
            "title": .string(title),
            "databaseTitle": .string(databaseTitle),
            "assignees": .array(assignees.map(JSONValue.string)),
            "isOverdue": .bool(isOverdue),
        ]
        if let dueISO { object["dueISO"] = .string(dueISO) }
        if let url { object["url"] = .string(url) }
        return .object(object)
    }

    /// Reconstructs an envelope from a stashed ``JSONValue`` (nil if malformed).
    init?(json: JSONValue) {
        guard let pageId = json["pageId"]?.string,
              let title = json["title"]?.string,
              let databaseTitle = json["databaseTitle"]?.string
        else { return nil }
        self.pageId = pageId
        self.title = title
        self.databaseTitle = databaseTitle
        dueISO = json["dueISO"]?.string
        assignees = json["assignees"]?.array?.compactMap(\.string) ?? []
        url = json["url"]?.string
        isOverdue = json["isOverdue"]?.bool ?? false
    }

    /// Creates an envelope to stash during fetch.
    init(
        pageId: String,
        title: String,
        databaseTitle: String,
        dueISO: String?,
        assignees: [String],
        url: String?,
        isOverdue: Bool
    ) {
        self.pageId = pageId
        self.title = title
        self.databaseTitle = databaseTitle
        self.dueISO = dueISO
        self.assignees = assignees
        self.url = url
        self.isOverdue = isOverdue
    }
}
