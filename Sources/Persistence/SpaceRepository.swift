import DaybriefCore
import Foundation
import GRDB

/// Reads and writes ``Space`` values. Async, serialized through the injected
/// `DatabaseQueue`.
public struct SpaceRepository: Sendable {
    private let queue: DatabaseQueue

    /// Creates a repository over the given database queue (the DI seam).
    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// Inserts or updates a space (keyed by id).
    public func save(_ space: Space) async throws {
        let record = SpaceRecord(space)
        try await queue.write { db in
            try record.save(db)
        }
    }

    /// Returns all spaces, ordered by their stable key.
    public func all() async throws -> [Space] {
        let records = try await queue.read { db in
            try SpaceRecord.order(Column("key")).fetchAll(db)
        }
        return try records.map { try $0.toCore() }
    }

    /// Returns the space with the given key, or `nil`.
    public func space(forKey key: String) async throws -> Space? {
        let record = try await queue.read { db in
            try SpaceRecord.filter(Column("key") == key).fetchOne(db)
        }
        return try record?.toCore()
    }

    /// Deletes the space with the given id. Returns `true` if a row was removed.
    @discardableResult
    public func delete(id: UUID) async throws -> Bool {
        let key = id.uuidString
        return try await queue.write { db in
            try SpaceRecord.deleteOne(db, key: key)
        }
    }
}
