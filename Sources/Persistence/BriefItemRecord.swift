import DaybriefCore
import Foundation
import GRDB

/// GRDB row for the `brief_items` table — one row per normalized ``BriefItem``.
///
/// Normalized into its own table (rather than folded into the brief JSON) so it
/// can back the future FTS5 chat-context index and traceability. Carries a
/// nullable `brief_id` linking it to the brief it fed. List-valued fields are
/// stored as JSON text.
struct BriefItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "brief_items"

    var id: String
    var briefId: String?
    var source: String
    var account: String
    var space: String
    var type: String
    var title: String
    var body: String?
    var peopleJSON: String
    var timestamp: Date
    var url: String?
    var urgencyHintsJSON: String

    enum CodingKeys: String, CodingKey {
        case id
        case briefId = "brief_id"
        case source
        case account
        case space
        case type
        case title
        case body
        case peopleJSON = "people_json"
        case timestamp
        case url
        case urgencyHintsJSON = "urgency_hints_json"
    }
}

extension BriefItemRecord {
    /// Builds a row from a ``BriefItem``, optionally linked to a brief.
    init(_ item: BriefItem, briefID: UUID? = nil) throws {
        id = item.id.uuidString
        briefId = briefID?.uuidString
        source = item.source.rawValue
        account = item.account
        space = item.space
        type = item.type.rawValue
        title = item.title
        body = item.body
        peopleJSON = try JSONColumn.encode(item.people)
        timestamp = item.timestamp
        url = item.url?.absoluteString
        urgencyHintsJSON = try JSONColumn.encode(item.urgencyHints.map(\.rawValue))
    }

    /// Maps the row back to a ``BriefItem``.
    func toCore() throws -> BriefItem {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(entity: "BriefItem", detail: "invalid UUID '\(id)'")
        }
        let people = try JSONColumn.decode([String].self, from: peopleJSON, entity: "BriefItem.people")
        let hintStrings = try JSONColumn.decode(
            [String].self,
            from: urgencyHintsJSON,
            entity: "BriefItem.urgencyHints"
        )
        return BriefItem(
            id: uuid,
            source: ConnectorID(source),
            account: account,
            space: space,
            type: ItemType(rawValue: type),
            title: title,
            body: body,
            people: people,
            timestamp: timestamp,
            url: url.flatMap(URL.init(string:)),
            urgencyHints: hintStrings.map(UrgencyHint.init(rawValue:))
        )
    }
}
