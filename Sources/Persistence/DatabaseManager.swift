import Foundation
import GRDB
import os

/// Opens and migrates the Daybrief SQLite store and exposes the
/// `DatabaseQueue` as the dependency-injection seam for repositories.
///
/// Two construction modes:
/// - ``init(url:encryptionKey:)`` opens a database file on disk (production).
/// - ``inMemory()`` opens a private in-memory database (tests).
///
/// In both modes the v1 schema (`spaces`, `connections`, `accounts`, `briefs`,
/// `brief_items`, `settings`) is created via a `DatabaseMigrator` before the
/// queue is handed out, so callers always receive a ready, migrated store.
///
/// ### Encryption
/// When an `encryptionKey` is provided **and** the build is SQLCipher-enabled,
/// the raw 256-bit key is applied as `PRAGMA key = "x'<hex>'"` inside
/// `Configuration.prepareDatabase` (no KDF). The default SPM build ships plain
/// GRDB, where the `usePassphrase` symbol does not exist; there, supplying a key
/// throws ``PersistenceError/encryptionUnavailable`` rather than silently writing
/// an unencrypted file. Enabling SQLCipher is a documented build task
/// (`docs/build/grdb-sqlcipher.md`).
public struct DatabaseManager: Sendable {
    /// The migrated database queue. This is the DI seam: repositories are
    /// constructed against this writer, and tests inject an in-memory one.
    public let queue: DatabaseQueue

    private static let logger = Logger(subsystem: "co.daybrief.persistence", category: "DatabaseManager")

    /// Opens (creating if needed) and migrates the database at `url`.
    ///
    /// - Parameters:
    ///   - url: The on-disk location of the SQLite file. Intermediate
    ///     directories are created if they do not exist.
    ///   - encryptionKey: A raw 32-byte (256-bit) SQLCipher key. When `nil`
    ///     the database is opened unencrypted (the default SPM build). When
    ///     non-`nil` on a non-SQLCipher build, this throws
    ///     ``PersistenceError/encryptionUnavailable``.
    public init(url: URL, encryptionKey: Data? = nil) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = try Self.makeConfiguration(encryptionKey: encryptionKey)
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try Self.migrator.migrate(queue)
        self.queue = queue
        Self.logger.debug("Opened database at \(url.path, privacy: .private)")
    }

    private init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// Opens a private in-memory database and runs the migrator. For tests.
    ///
    /// In-memory databases are never encrypted (there is no file at rest), so no
    /// key is accepted here.
    public static func inMemory() throws -> DatabaseManager {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return DatabaseManager(queue: queue)
    }

    /// Builds the GRDB `Configuration`, applying the SQLCipher raw key when one
    /// is provided and the build supports it.
    private static func makeConfiguration(encryptionKey: Data?) throws -> Configuration {
        var configuration = Configuration()

        // No key → plain, unencrypted database (the default SPM build).
        guard let key = encryptionKey else {
            return configuration
        }

        // TODO(SQLCipher): the `usePassphrase` API only exists in a
        // SQLCipher-enabled GRDB build (it lives behind `#if SQLITE_HAS_CODEC`
        // in GRDB's `Database+SQLCipher.swift`). The default SPM build is plain
        // GRDB and that symbol is absent — referencing it unconditionally would
        // not compile. We therefore gate on the same `SQLCipher` define GRDB's
        // fork sets (see docs/build/grdb-sqlcipher.md). On the default build,
        // requesting a key is an error rather than a silent plaintext write.
        #if SQLCipher
            // Hex-encode the raw 256-bit key into the SQLCipher raw-key literal.
            let rawKeyLiteral = "x'" + key.map { String(format: "%02x", $0) }.joined() + "'"
            // Load/apply the key *inside* prepareDatabase so it is not captured in
            // the Configuration for the connection's lifetime, and so that opening
            // fails cleanly if the key is wrong/unavailable. The raw `x'…'` literal
            // makes SQLCipher use the bytes directly with no PBKDF2 derivation.
            configuration.prepareDatabase { db in
                try db.usePassphrase(rawKeyLiteral)
            }
            return configuration
        #else
            _ = key // silence "unused" on the non-SQLCipher build; the throw is the point.
            throw PersistenceError.encryptionUnavailable
        #endif
    }

    /// The schema migrator. A single `v1` migration creates every table; future
    /// schema changes append new migrations (never edit `v1`).
    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        #if DEBUG
            // Speeds local iteration only; never enabled in release (it wipes data).
            migrator.eraseDatabaseOnSchemaChange = true
        #endif
        Migrations.registerV1(&migrator)
        Migrations.registerV2(&migrator)
        return migrator
    }()
}
