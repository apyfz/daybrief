import Foundation

/// RFC3339 date formatting for Calendar API query parameters.
///
/// The Calendar API requires `timeMin`/`timeMax` as RFC3339 timestamps **with a timezone
/// offset** (e.g. `2026-06-17T00:00:00-07:00` or `…Z`); a bare local time is rejected.
/// `ISO8601DateFormatter` with `.withInternetDateTime` emits the offset, so the request
/// window matches the user's local "today" rather than UTC.
enum RFC3339 {
    // Formatters are documented thread-safe for format/parse, but the type itself is not
    // `Sendable`; the `nonisolated(unsafe)` shared instances are only ever read, never mutated.

    /// Parses an RFC3339 `dateTime` value, with or without fractional seconds.
    private nonisolated(unsafe) static let reader: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let readerWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Formats `date` as an RFC3339 string carrying `timeZone`'s UTC offset
    /// (e.g. `2026-06-17T00:00:00-07:00`). The zone is injected (rather than read
    /// from `TimeZone.current`) so the rendered wall-clock is deterministic — the
    /// window is built in the reader's local "today", which the connector passes in.
    ///
    /// A fresh formatter is created per call: `ISO8601DateFormatter`'s `timeZone`
    /// is mutable state, so sharing one instance across timezones would be unsafe
    /// under concurrency. Window formatting happens once per fetch, so this is cheap.
    static func string(from date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// Parses an RFC3339 `dateTime` string (with or without fractional seconds), else `nil`.
    static func date(from string: String) -> Date? {
        reader.date(from: string) ?? readerWithFraction.date(from: string)
    }
}
