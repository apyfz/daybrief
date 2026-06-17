import DaybriefCore
import Foundation
import GRDB

/// Reads and writes ``Brief`` values. Async, serialized through the injected
/// `DatabaseQueue`.
///
/// `sections` and `connectorErrors` are stored as JSON on the `briefs` row;
/// the normalized ``BriefItem`` values a brief was synthesized from are stored
/// separately via ``saveItems(_:briefID:)`` (M1+ wiring backs the FTS index).
public struct BriefRepository: Sendable {
    private let queue: DatabaseQueue

    /// Creates a repository over the given database queue (the DI seam).
    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// Inserts or updates a brief (keyed by id).
    public func save(_ brief: Brief) async throws {
        let record = try BriefRecord(brief)
        try await queue.write { db in
            try record.save(db)
        }
    }

    /// Persists the normalized items a brief was synthesized from, linking each
    /// to `briefID`. Existing items for that brief are replaced.
    public func saveItems(_ items: [BriefItem], briefID: UUID) async throws {
        let key = briefID.uuidString
        let records = try items.map { try BriefItemRecord($0, briefID: briefID) }
        try await queue.write { db in
            try BriefItemRecord.filter(Column("brief_id") == key).deleteAll(db)
            for record in records {
                try record.insert(db)
            }
        }
    }

    /// Returns the most recently generated brief, or `nil` if none exist.
    public func loadLatest() async throws -> Brief? {
        let record = try await queue.read { db in
            try BriefRecord.order(Column("generated_at").desc).fetchOne(db)
        }
        return try record?.toCore()
    }

    /// Returns briefs newest-first, optionally capped at `limit`.
    public func list(limit: Int? = nil) async throws -> [Brief] {
        let records = try await queue.read { db -> [BriefRecord] in
            let request = BriefRecord.order(Column("generated_at").desc)
            if let limit {
                return try request.limit(limit).fetchAll(db)
            }
            return try request.fetchAll(db)
        }
        return try records.map { try $0.toCore() }
    }

    /// Returns the normalized items linked to the given brief, newest-first.
    public func items(forBriefID briefID: UUID) async throws -> [BriefItem] {
        let key = briefID.uuidString
        let records = try await queue.read { db in
            try BriefItemRecord
                .filter(Column("brief_id") == key)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return try records.map { try $0.toCore() }
    }

    /// Deletes the brief with the given id. Its items cascade-delete.
    /// Returns `true` if a row was removed.
    @discardableResult
    public func delete(id: UUID) async throws -> Bool {
        let key = id.uuidString
        return try await queue.write { db in
            try BriefRecord.deleteOne(db, key: key)
        }
    }
}
