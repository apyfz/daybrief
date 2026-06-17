import DaybriefCore
import Foundation

/// The wall-clock fire-time the daily brief is scheduled for, as local hour/minute.
public struct FireTime: Sendable, Equatable, Hashable {
    /// Hour of day, 0–23.
    public let hour: Int
    /// Minute of hour, 0–59.
    public let minute: Int

    /// Creates a fire time, clamping `hour` to 0–23 and `minute` to 0–59.
    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Parses a `"HH:mm"` string (the `SettingsStore.briefTime` encoding), or `nil`.
    public init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0 ... 23).contains(hour),
              (0 ... 59).contains(minute)
        else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// The `"HH:mm"` encoding (zero-padded), matching `SettingsStore.briefTime`.
    public var encoded: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// Pure scheduling logic for the daily brief: decide whether a brief is due *now*
/// (the wake/launch catch-up semantics) and compute the next fire date.
///
/// No AppKit, no timers, no notifications — those live in `AppFeature`, which
/// drives this type from its `DispatchSourceTimer` event handler, its
/// `NSWorkspace.didWakeNotification` observer, and at launch (design §12). All
/// three entry points route through the same idempotent decision here, so
/// "generate on next wake/open if the fire-time was missed" falls out for free.
///
/// The catch-up rule (verified, research §scheduling): generate now when
/// **today's local fire-time has already passed** *and* **we have not generated a
/// brief today** (`lastRunDate` is not today). Persisting only the calendar day
/// makes the once-per-day guarantee timezone-stable and robust to a manual
/// "Generate now", multiple wakes, and a late timer fire all landing the same day.
public struct BriefScheduler: Sendable {
    /// The configured local fire-time.
    public let fireTime: FireTime
    private let calendar: Calendar

    /// Creates a scheduler for `fireTime`.
    ///
    /// - Parameters:
    ///   - fireTime: The user's local fire-time.
    ///   - calendar: The calendar used for all wall-clock math (injectable so tests
    ///     can pin the timezone; defaults to `.current`).
    public init(fireTime: FireTime, calendar: Calendar = .current) {
        self.fireTime = fireTime
        self.calendar = calendar
    }

    /// Whether a brief should be generated right now.
    ///
    /// `true` when today's fire-time has passed (relative to `now`) **and** no
    /// brief has been generated today (`lastRunDate` is `nil` or on an earlier
    /// calendar day). Idempotent: calling it repeatedly the same day after a run
    /// returns `false` until the next day.
    ///
    /// - Parameters:
    ///   - now: The current instant (from a ``DaybriefCore/DateProvider``).
    ///   - lastRunDate: The instant a brief was last successfully generated, or
    ///     `nil` if never. Only its calendar day matters.
    /// - Returns: `true` if a brief is due now.
    public func shouldGenerateNow(now: Date, lastRunDate: Date?) -> Bool {
        guard now >= todaysFireDate(now: now) else { return false }
        guard let lastRunDate else { return true }
        return !calendar.isDate(lastRunDate, inSameDayAs: now)
    }

    /// Whether the wake/launch catch-up should generate a brief right now,
    /// accounting for a **failed** attempt earlier today.
    ///
    /// Like ``shouldGenerateNow(now:lastRunDate:)`` this fires only once the
    /// fire-time has passed, but it suppresses generation when *either* a brief
    /// was successfully generated today (`lastSuccessDate`) *or* an attempt was
    /// already made today (`lastAttemptDate`). Recording the attempt on every
    /// run — success or failure — is what makes a failed generation back off for
    /// the rest of the day instead of re-firing (and re-spending on the LLM) on
    /// every subsequent wake. The manual "Generate now" path does not consult
    /// this gate, so the user can always retry by hand.
    ///
    /// - Parameters:
    ///   - now: The current instant (from a ``DaybriefCore/DateProvider``).
    ///   - lastSuccessDate: The instant a brief was last successfully generated,
    ///     or `nil`. Only its calendar day matters.
    ///   - lastAttemptDate: The instant a brief was last *attempted* (success or
    ///     failure), or `nil`. Only its calendar day matters.
    /// - Returns: `true` if the catch-up should generate now.
    public func shouldGenerateOnCatchUp(
        now: Date,
        lastSuccessDate: Date?,
        lastAttemptDate: Date?
    ) -> Bool {
        guard now >= todaysFireDate(now: now) else { return false }
        if let lastSuccessDate, calendar.isDate(lastSuccessDate, inSameDayAs: now) {
            return false
        }
        if let lastAttemptDate, calendar.isDate(lastAttemptDate, inSameDayAs: now) {
            return false
        }
        return true
    }

    /// The next moment the daily timer should fire, as an absolute `Date`.
    ///
    /// This is the next *future* occurrence of the fire-time strictly after `now`,
    /// computed via `Calendar.nextDate(after:matching:)` so it is DST-safe and
    /// never drifts. Use this to arm the next one-shot timer; it intentionally does
    /// not encode catch-up — that is ``shouldGenerateNow(now:lastRunDate:)``'s job,
    /// run on wake/launch.
    ///
    /// - Parameter now: The current instant.
    /// - Returns: The next fire `Date` strictly after `now`.
    public func nextFireDate(now: Date) -> Date {
        let components = DateComponents(hour: fireTime.hour, minute: fireTime.minute)
        if let next = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) {
            return next
        }
        // Defensive fallback (Calendar.nextDate is documented to find a match for a
        // valid hour/minute): roll forward a day from today's fire-time.
        let today = todaysFireDate(now: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Today's fire-time as an absolute `Date` (today's date at `fireTime`).
    func todaysFireDate(now: Date) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(
            bySettingHour: fireTime.hour,
            minute: fireTime.minute,
            second: 0,
            of: startOfToday
        ) ?? startOfToday
    }
}
