import DaybriefCore
import Foundation
import GRDB

/// A typed wrapper over the `settings` key/value table.
///
/// Stores small scalar app preferences — the daily brief fire-time, the
/// selected LLM model id, the catch-up `lastBriefDate`, etc. Values are stored
/// as text; typed accessors encode/decode on the way through. Async, serialized
/// through the injected `DatabaseQueue`.
public struct SettingsStore: Sendable {
    /// A namespaced, type-safe settings key. Wrapping the raw string in a
    /// generic key keeps call sites honest about each value's type.
    public struct Key<Value>: Sendable {
        /// The raw column key.
        public let name: String
        /// Creates a key with the given raw name.
        public init(_ name: String) {
            self.name = name
        }
    }

    private let queue: DatabaseQueue

    /// Creates a settings store over the given database queue (the DI seam).
    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - Raw string access

    /// Returns the raw stored string for `key`, or `nil`.
    public func string(forKey key: String) async throws -> String? {
        try await queue.read { db in
            try SettingRecord.fetchOne(db, key: key)?.value
        }
    }

    /// Sets (or, when `value` is `nil`, removes) the raw string for `key`.
    public func setString(_ value: String?, forKey key: String) async throws {
        try await queue.write { db in
            if let value {
                try SettingRecord(key: key, value: value).save(db)
            } else {
                _ = try SettingRecord.deleteOne(db, key: key)
            }
        }
    }

    // MARK: - Typed access

    /// Returns the decoded value for a typed `LosslessStringConvertible` key.
    public func get<Value: LosslessStringConvertible>(_ key: Key<Value>) async throws -> Value? {
        guard let raw = try await string(forKey: key.name) else { return nil }
        guard let value = Value(raw) else {
            throw PersistenceError.corruptRow(entity: "settings[\(key.name)]", detail: "could not parse '\(raw)'")
        }
        return value
    }

    /// Sets (or removes when `nil`) the value for a typed
    /// `LosslessStringConvertible` key.
    public func set<Value: LosslessStringConvertible>(_ value: Value?, for key: Key<Value>) async throws {
        // `description` is the exact inverse of `Value(_:)` for LosslessStringConvertible.
        try await setString(value.map(\.description), forKey: key.name)
    }

    // MARK: - Date access (ISO-8601, deterministic)

    /// Returns the stored `Date` for `key`, parsed from ISO-8601, or `nil`.
    public func date(forKey key: String) async throws -> Date? {
        guard let raw = try await string(forKey: key) else { return nil }
        guard let date = SettingsStore.iso8601.date(from: raw) else {
            throw PersistenceError.corruptRow(entity: "settings[\(key)]", detail: "invalid ISO-8601 date '\(raw)'")
        }
        return date
    }

    /// Sets (or removes when `nil`) the ISO-8601-encoded `Date` for `key`.
    public func setDate(_ value: Date?, forKey key: String) async throws {
        try await setString(value.map { SettingsStore.iso8601.string(from: $0) }, forKey: key)
    }

    /// ISO8601DateFormatter is documented thread-safe for format/parse; the type
    /// is not marked Sendable, so opt out explicitly for this shared instance.
    private nonisolated(unsafe) static let iso8601 = ISO8601DateFormatter()

    // MARK: - Well-known keys

    /// The daily brief fire-time, encoded as `"HH:mm"` local wall-clock.
    public static let briefTime = Key<String>("brief_time")
    /// The selected LLM model id (e.g. an OpenRouter model slug).
    public static let selectedModel = Key<String>("selected_model")
    /// The provider id backing the selected model (e.g. `"openrouter"`).
    public static let selectedProvider = Key<String>("selected_provider")
    /// Whether launch-at-login is desired (the live source of truth is
    /// `SMAppService.status`; this is only a remembered user preference).
    public static let launchAtLogin = Key<Bool>("launch_at_login")
    /// Raw key for the catch-up `lastBriefDate` (an ISO-8601 day); read/written
    /// via ``date(forKey:)`` / ``setDate(_:forKey:)``. Stamped only on a
    /// **successful** generation (see `RepositoryBriefSink`).
    public static let lastBriefDateKey = "last_brief_date"
    /// Raw key for the catch-up `lastBriefAttemptDate` (an ISO-8601 day);
    /// read/written via ``date(forKey:)`` / ``setDate(_:forKey:)``. Stamped on
    /// **every** generation attempt regardless of outcome, so a failed brief
    /// backs off the wake/launch catch-up for the rest of the day instead of
    /// re-firing (and re-spending on the LLM) on every wake.
    public static let lastBriefAttemptDateKey = "last_brief_attempt_date"
}

/// GRDB row for the `settings` table.
private struct SettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "settings"
    var key: String
    var value: String
}
