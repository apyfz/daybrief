import DaybriefCore
import Foundation

/// A Calendar event's start, normalized across the two shapes Google returns.
///
/// Timed events carry `start.dateTime` (RFC3339 with offset); all-day events carry
/// `start.date` (`yyyy-MM-dd`, no time). `EventStart` resolves either into a concrete
/// ``date`` for the brief item's timestamp and remembers whether it was an all-day event,
/// so "today" can be computed correctly in the event's own day boundaries.
struct EventStart {
    /// The resolved start instant (the day's start, in the event timezone, for all-day events).
    let date: Date
    /// Whether the source was an all-day `start.date` value.
    let isAllDay: Bool
    /// The event's timezone, if `start.timeZone` was present; otherwise the device timezone.
    let timeZone: TimeZone

    /// Builds an `EventStart` from a `start` JSON object, preferring `dateTime` over `date`.
    ///
    /// - Parameter fallbackTimeZone: the zone used when the event omits `start.timeZone`
    ///   (notably all-day events, which carry only a floating `yyyy-MM-dd`). Injected so
    ///   "today" is judged in the reader's chosen zone deterministically, not the wall-clock
    ///   `TimeZone.current` of whatever host the code runs on.
    init?(from start: JSONValue?, fallbackTimeZone: TimeZone) {
        guard let start else { return nil }

        let zone = (start["timeZone"]?.string).flatMap(TimeZone.init(identifier:)) ?? fallbackTimeZone

        if let dateTime = start["dateTime"]?.string, let parsed = RFC3339.date(from: dateTime) {
            date = parsed
            isAllDay = false
            timeZone = zone
            return
        }

        if let dateOnly = start["date"]?.string {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = zone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let parsed = formatter.date(from: dateOnly) else { return nil }
            date = parsed
            isAllDay = true
            timeZone = zone
            return
        }

        return nil
    }

    /// Whether this start falls on the same calendar day as `reference`, judged in the
    /// event's timezone (so an all-day event "today" is tagged regardless of the device clock).
    func isOnSameDay(as reference: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: reference)
    }
}
