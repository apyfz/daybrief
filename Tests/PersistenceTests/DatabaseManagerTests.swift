import DaybriefCore
import Foundation
import GRDB
@testable import Persistence
import Testing

@Suite("DatabaseManager")
struct DatabaseManagerTests {
    @Test("inMemory() runs the v1 migration, creating every table")
    func migrationCreatesTables() async throws {
        let manager = try DatabaseManager.inMemory()

        let tables = try await manager.queue.read { db -> Set<String> in
            let names = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            return Set(names)
        }

        for expected in ["spaces", "connections", "accounts", "briefs", "brief_items", "settings"] {
            #expect(tables.contains(expected), "missing table \(expected)")
        }
    }

    @Test("the v1 migration is recorded as applied")
    func migrationRecorded() async throws {
        let manager = try DatabaseManager.inMemory()
        let applied = try await manager.queue.read { db in
            try DatabaseManager.migrator.appliedMigrations(db)
        }
        #expect(applied == ["v1"])
    }

    @Test("opening a file-backed database creates and migrates it")
    func fileBackedOpens() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daybrief-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("daybrief.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let manager = try DatabaseManager(url: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let applied = try await manager.queue.read { db in
            try DatabaseManager.migrator.appliedMigrations(db)
        }
        #expect(applied == ["v1"])
    }

    @Test("requesting encryption on the default (plain GRDB) build throws")
    func encryptionUnavailableOnDefaultBuild() throws {
        // On the default SPM build there is no SQLCipher, so an encryption key
        // must be rejected rather than silently writing plaintext.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daybrief-enc-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("daybrief.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let key = Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })

        #if SQLCipher
            // A SQLCipher build should accept the key and open successfully.
            _ = try DatabaseManager(url: url, encryptionKey: key)
        #else
            #expect(throws: PersistenceError.encryptionUnavailable) {
                _ = try DatabaseManager(url: url, encryptionKey: key)
            }
        #endif
    }
}
