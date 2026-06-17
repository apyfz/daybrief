import DaybriefCore
import Foundation
import GRDB

/// GRDB row for the `spaces` table. Kept separate from ``Space`` so that
/// `DaybriefCore` never imports GRDB.
struct SpaceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "spaces"

    var id: String
    var key: String
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case displayName = "display_name"
    }
}

extension SpaceRecord {
    /// Builds a row from a ``Space``.
    init(_ space: Space) {
        id = space.id.uuidString
        key = space.key
        displayName = space.displayName
    }

    /// Maps the row back to a ``Space``.
    func toCore() throws -> Space {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(entity: "Space", detail: "invalid UUID '\(id)'")
        }
        return Space(id: uuid, key: key, displayName: displayName)
    }
}
