import DaybriefCore
import Foundation
import GRDB

/// GRDB row for the `accounts` table. Carries a foreign key to its owning
/// connection and the Keychain `secretRef` coordinates — **never** token bytes.
struct AccountRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "accounts"

    var id: String
    var connectionId: String
    var connectorId: String
    var label: String
    var spaceKey: String
    var secretService: String
    var secretAccount: String

    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case connectorId = "connector_id"
        case label
        case spaceKey = "space_key"
        case secretService = "secret_service"
        case secretAccount = "secret_account"
    }
}

extension AccountRecord {
    /// Builds a row from an ``Account`` for the given owning connection.
    init(_ account: Account, connectionID: UUID) {
        id = account.id.uuidString
        connectionId = connectionID.uuidString
        connectorId = account.connectorId.rawValue
        label = account.label
        spaceKey = account.spaceKey
        secretService = account.secretRef.service
        secretAccount = account.secretRef.account
    }

    /// Maps the row back to an ``Account``.
    func toCore() throws -> Account {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(entity: "Account", detail: "invalid UUID '\(id)'")
        }
        return Account(
            id: uuid,
            connectorId: ConnectorID(connectorId),
            label: label,
            spaceKey: spaceKey,
            secretRef: SecretRef(service: secretService, account: secretAccount)
        )
    }
}
