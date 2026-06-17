import DaybriefCore
import Foundation
import GRDB

/// GRDB row for the `connections` table. The connection's accounts live in the
/// separate `accounts` table (see ``AccountRecord``) and are assembled by
/// ``ConnectionRepository``.
struct ConnectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "connections"

    var id: String
    var connectorId: String
    var displayName: String
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case connectorId = "connector_id"
        case displayName = "display_name"
        case isEnabled = "is_enabled"
    }
}

extension ConnectionRecord {
    /// Builds a row from a ``Connection`` (accounts persisted separately).
    init(_ connection: Connection) {
        id = connection.id.uuidString
        connectorId = connection.connectorId.rawValue
        displayName = connection.displayName
        isEnabled = connection.isEnabled
    }

    /// Maps the row plus its already-loaded accounts back to a ``Connection``.
    func toCore(accounts: [Account]) throws -> Connection {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(entity: "Connection", detail: "invalid UUID '\(id)'")
        }
        return Connection(
            id: uuid,
            connectorId: ConnectorID(connectorId),
            displayName: displayName,
            accounts: accounts,
            isEnabled: isEnabled
        )
    }
}
