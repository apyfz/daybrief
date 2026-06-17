import DaybriefCore
import Foundation
import GRDB

/// Reads and writes ``Connection`` values together with their ``Account``
/// children. Async, serialized through the injected `DatabaseQueue`.
///
/// A connection and its accounts are saved in a single transaction; the account
/// set is replaced wholesale on each save (delete-then-insert) so the stored
/// graph exactly matches the supplied ``Connection``.
public struct ConnectionRepository: Sendable {
    private let queue: DatabaseQueue

    /// Creates a repository over the given database queue (the DI seam).
    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// Inserts or updates a connection and replaces its accounts atomically.
    public func save(_ connection: Connection) async throws {
        let connectionRecord = ConnectionRecord(connection)
        let accountRecords = connection.accounts.map { AccountRecord($0, connectionID: connection.id) }
        try await queue.write { db in
            try connectionRecord.save(db)
            // Replace the account set wholesale so removed accounts disappear.
            try AccountRecord
                .filter(Column("connection_id") == connectionRecord.id)
                .deleteAll(db)
            for record in accountRecords {
                try record.insert(db)
            }
        }
    }

    /// Returns all connections with their accounts, ordered by display name.
    public func all() async throws -> [Connection] {
        try await queue.read { db in
            let connectionRecords = try ConnectionRecord
                .order(Column("display_name"))
                .fetchAll(db)
            return try connectionRecords.map { record in
                let accounts = try AccountRecord
                    .filter(Column("connection_id") == record.id)
                    .order(Column("label"))
                    .fetchAll(db)
                    .map { try $0.toCore() }
                return try record.toCore(accounts: accounts)
            }
        }
    }

    /// Returns the connection with the given id (with its accounts), or `nil`.
    public func connection(id: UUID) async throws -> Connection? {
        let key = id.uuidString
        return try await queue.read { db in
            guard let record = try ConnectionRecord.fetchOne(db, key: key) else {
                return nil
            }
            let accounts = try AccountRecord
                .filter(Column("connection_id") == key)
                .order(Column("label"))
                .fetchAll(db)
                .map { try $0.toCore() }
            return try record.toCore(accounts: accounts)
        }
    }

    /// Deletes the connection with the given id. Its accounts cascade-delete.
    /// Returns `true` if a row was removed.
    @discardableResult
    public func delete(id: UUID) async throws -> Bool {
        let key = id.uuidString
        return try await queue.write { db in
            try ConnectionRecord.deleteOne(db, key: key)
        }
    }
}
