import DaybriefCore
import Foundation
@testable import Pipeline
import Testing

@Suite("BriefScheduler catch-up logic")
struct BriefSchedulerTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Builds a UTC date at the given wall-clock.
    private static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (y, mo, d, h, mi)
        return utcCalendar.date(from: c)!
    }

    private func scheduler(hour: Int, minute: Int) -> BriefScheduler {
        BriefScheduler(fireTime: FireTime(hour: hour, minute: minute), calendar: Self.utcCalendar)
    }

    // MARK: shouldGenerateNow

    @Test("before today's fire-time → do not generate")
    func beforeFireTime() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 6, 30) // 06:30, before 07:00
        #expect(s.shouldGenerateNow(now: now, lastRunDate: nil) == false)
    }

    @Test("after fire-time and never run → generate (first launch)")
    func afterFireTimeNeverRun() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 9, 0) // 09:00, after 07:00
        #expect(s.shouldGenerateNow(now: now, lastRunDate: nil) == true)
    }

    @Test("after fire-time but already ran today → suppress duplicate")
    func afterFireTimeAlreadyRanToday() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 9, 0)
        let ranThisMorning = Self.date(2026, 6, 17, 7, 1)
        #expect(s.shouldGenerateNow(now: now, lastRunDate: ranThisMorning) == false)
    }

    @Test("after fire-time and last run was yesterday → generate (catch-up)")
    func catchUpAfterMissedDay() {
        let s = scheduler(hour: 7, minute: 0)
        // Woke at 10:00 today; last brief was yesterday morning.
        let now = Self.date(2026, 6, 17, 10, 0)
        let ranYesterday = Self.date(2026, 6, 16, 7, 5)
        #expect(s.shouldGenerateNow(now: now, lastRunDate: ranYesterday) == true)
    }

    @Test("exactly at fire-time → generate (boundary is inclusive)")
    func exactlyAtFireTime() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 7, 0)
        #expect(s.shouldGenerateNow(now: now, lastRunDate: nil) == true)
    }

    @Test("before fire-time with a stale last run still does not generate early")
    func beforeFireTimeWithStaleRun() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 6, 0) // before fire-time
        let ranLastWeek = Self.date(2026, 6, 10, 7, 0)
        // Fire-time hasn't passed yet today, so even a stale run shouldn't trigger.
        #expect(s.shouldGenerateNow(now: now, lastRunDate: ranLastWeek) == false)
    }

    // MARK: shouldGenerateOnCatchUp (failure back-off)

    @Test("catch-up: due and no attempt today → generate")
    func catchUpDueNoAttempt() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 9, 0) // after 07:00
        #expect(s.shouldGenerateOnCatchUp(now: now, lastSuccessDate: nil, lastAttemptDate: nil) == true)
    }

    @Test("catch-up: due but an attempt was already made today → skip (failure back-off)")
    func catchUpDueAttemptToday() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 12, 0)
        // A brief was attempted at 07:01 and failed — `lastSuccessDate` is still
        // yesterday (or nil), but the attempt today must suppress a re-fire.
        let attemptedThisMorning = Self.date(2026, 6, 17, 7, 1)
        #expect(
            s.shouldGenerateOnCatchUp(
                now: now,
                lastSuccessDate: nil,
                lastAttemptDate: attemptedThisMorning
            ) == false
        )
    }

    @Test("catch-up: due, succeeded today → skip even if attempt is nil")
    func catchUpDueSucceededToday() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 12, 0)
        let succeededThisMorning = Self.date(2026, 6, 17, 7, 2)
        #expect(
            s.shouldGenerateOnCatchUp(
                now: now,
                lastSuccessDate: succeededThisMorning,
                lastAttemptDate: nil
            ) == false
        )
    }

    @Test("catch-up: due, last attempt was yesterday → generate (new day)")
    func catchUpDueAttemptYesterday() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 10, 0)
        // Yesterday's brief failed; today is a fresh day so we should try again.
        let attemptedYesterday = Self.date(2026, 6, 16, 7, 1)
        #expect(
            s.shouldGenerateOnCatchUp(
                now: now,
                lastSuccessDate: nil,
                lastAttemptDate: attemptedYesterday
            ) == true
        )
    }

    @Test("catch-up: before fire-time → do not generate even with no attempt")
    func catchUpBeforeFireTime() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 6, 30) // before 07:00
        #expect(s.shouldGenerateOnCatchUp(now: now, lastSuccessDate: nil, lastAttemptDate: nil) == false)
    }

    @Test("catch-up: due, succeeded and attempted today → skip")
    func catchUpDueSucceededAndAttemptedToday() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 18, 0)
        let today = Self.date(2026, 6, 17, 7, 0)
        #expect(
            s.shouldGenerateOnCatchUp(
                now: now,
                lastSuccessDate: today,
                lastAttemptDate: today
            ) == false
        )
    }

    // MARK: nextFireDate

    @Test("next fire is later today when now is before fire-time")
    func nextFireLaterToday() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 6, 30)
        let next = s.nextFireDate(now: now)
        #expect(next == Self.date(2026, 6, 17, 7, 0))
    }

    @Test("next fire rolls to tomorrow when now is past today's fire-time")
    func nextFireRollsToTomorrow() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 9, 0)
        let next = s.nextFireDate(now: now)
        #expect(next == Self.date(2026, 6, 18, 7, 0))
    }

    @Test("next fire is strictly after now even exactly at the fire-time")
    func nextFireStrictlyAfterNow() {
        let s = scheduler(hour: 7, minute: 0)
        let now = Self.date(2026, 6, 17, 7, 0)
        let next = s.nextFireDate(now: now)
        // .nextTime is strictly-after, so it rolls to tomorrow.
        #expect(next == Self.date(2026, 6, 18, 7, 0))
        #expect(next > now)
    }

    // MARK: FireTime parsing

    @Test("FireTime parses and re-encodes HH:mm")
    func fireTimeRoundTrips() throws {
        let parsed = try #require(FireTime("07:05"))
        #expect(parsed.hour == 7)
        #expect(parsed.minute == 5)
        #expect(parsed.encoded == "07:05")
    }

    @Test("FireTime rejects malformed strings")
    func fireTimeRejectsMalformed() {
        #expect(FireTime("7am") == nil)
        #expect(FireTime("25:00") == nil)
        #expect(FireTime("07:60") == nil)
        #expect(FireTime("07") == nil)
    }

    @Test("FireTime clamps out-of-range components")
    func fireTimeClamps() {
        #expect(FireTime(hour: 30, minute: -5) == FireTime(hour: 23, minute: 0))
    }
}
