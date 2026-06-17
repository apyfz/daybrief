import DaybriefCore
import Foundation
@testable import Pipeline
import Testing

@Suite("HeroArtworkCatalog determinism")
struct HeroArtworkCatalogTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func day(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (y, mo, d, 12)
        return utcCalendar.date(from: c)!
    }

    @Test("catalog is non-empty and all entries are public-domain references")
    func catalogIsPopulated() {
        #expect(HeroArtworkCatalog.all.count >= 10)
        for art in HeroArtworkCatalog.all {
            #expect(!art.assetName.isEmpty)
            #expect(!art.title.isEmpty)
            #expect(!art.artist.isEmpty)
        }
    }

    @Test("asset names are unique")
    func assetNamesAreUnique() {
        let names = HeroArtworkCatalog.all.map(\.assetName)
        #expect(Set(names).count == names.count)
    }

    @Test("the same date always selects the same artwork")
    func sameDateIsStable() {
        let date = Self.day(2026, 6, 17)
        let first = HeroArtworkCatalog.heroForDate(date, calendar: Self.utcCalendar)
        let second = HeroArtworkCatalog.heroForDate(date, calendar: Self.utcCalendar)
        #expect(first == second)
    }

    @Test("selection follows day-of-year modulo the catalog count")
    func selectionIsDayOfYearModulo() {
        // 1 Jan is day-of-year 1 → index 0.
        let jan1 = Self.day(2026, 1, 1)
        #expect(HeroArtworkCatalog.heroForDate(jan1, calendar: Self.utcCalendar) == HeroArtworkCatalog.all[0])

        // 2 Jan is day-of-year 2 → index 1.
        let jan2 = Self.day(2026, 1, 2)
        #expect(HeroArtworkCatalog.heroForDate(jan2, calendar: Self.utcCalendar) == HeroArtworkCatalog.all[1])
    }

    @Test("selection wraps around the catalog across a year")
    func selectionWraps() throws {
        let count = HeroArtworkCatalog.all.count
        // Day 1 and day (count + 1) map to the same index 0.
        let jan1 = Self.day(2026, 1, 1)
        let wrapDay = try #require(Self.utcCalendar.date(byAdding: .day, value: count, to: jan1))
        #expect(
            HeroArtworkCatalog.heroForDate(jan1, calendar: Self.utcCalendar)
                == HeroArtworkCatalog.heroForDate(wrapDay, calendar: Self.utcCalendar)
        )
    }

    @Test("consecutive days across the catalog span never crash and stay in range")
    func sweepAcrossYear() throws {
        let start = Self.day(2026, 1, 1)
        for offset in 0 ..< 400 {
            let date = try #require(Self.utcCalendar.date(byAdding: .day, value: offset, to: start))
            let art = HeroArtworkCatalog.heroForDate(date, calendar: Self.utcCalendar)
            #expect(HeroArtworkCatalog.all.contains(art))
        }
    }

    // MARK: - Per-edition accent

    @Test("every catalog entry carries a sampled #RRGGBB accent hex")
    func everyEntryHasAccentHex() {
        for art in HeroArtworkCatalog.all {
            let hex = art.accentHex
            #expect(hex != nil)
            guard let hex else { continue }
            #expect(hex.hasPrefix("#"))
            #expect(hex.count == 7)
            // Hex digits only after the leading '#'.
            let digits = hex.dropFirst()
            #expect(digits.allSatisfy { $0.isHexDigit })
        }
    }

    // MARK: - Tone-matched selection (heroForMood)

    @Test("every mood has at least one painting tagged for it")
    func everyMoodIsCovered() {
        for mood in BriefMood.allCases {
            let matches = HeroArtworkCatalog.tagged.filter { $0.moods.contains(mood) }
            #expect(!matches.isEmpty, "mood \(mood) has no tagged painting")
        }
    }

    @Test("heroForMood returns a painting tagged with that mood")
    func heroForMoodMatchesTag() {
        let date = Self.day(2026, 6, 17)
        for mood in BriefMood.allCases {
            let art = HeroArtworkCatalog.heroForMood(mood, date: date, calendar: Self.utcCalendar)
            let tagged = HeroArtworkCatalog.tagged.first { $0.artwork == art }
            #expect(tagged?.moods.contains(mood) == true, "heroForMood(\(mood)) returned an untagged painting")
        }
    }

    @Test("heroForMood is deterministic for the same mood + date")
    func heroForMoodIsDeterministic() {
        let date = Self.day(2026, 6, 17)
        let first = HeroArtworkCatalog.heroForMood(.eventful, date: date, calendar: Self.utcCalendar)
        let second = HeroArtworkCatalog.heroForMood(.eventful, date: date, calendar: Self.utcCalendar)
        #expect(first == second)
    }

    @Test("heroForMood selects deterministically by day-of-year within the match set")
    func heroForMoodIndexesByDayOfYear() {
        let matches = HeroArtworkCatalog.tagged.filter { $0.moods.contains(.busy) }.map(\.artwork)
        // 1 Jan is day-of-year 1 → index 0 within the busy-tagged subset.
        let jan1 = Self.day(2026, 1, 1)
        #expect(HeroArtworkCatalog.heroForMood(.busy, date: jan1, calendar: Self.utcCalendar) == matches[0])
        // 2 Jan → index 1 (if the subset has more than one painting).
        if matches.count > 1 {
            let jan2 = Self.day(2026, 1, 2)
            #expect(HeroArtworkCatalog.heroForMood(.busy, date: jan2, calendar: Self.utcCalendar) == matches[1])
        }
    }

    @Test("heroForMood with a nil mood falls back to the plain by-date pick")
    func heroForMoodNilFallsBackToDate() {
        let date = Self.day(2026, 6, 17)
        #expect(
            HeroArtworkCatalog.heroForMood(nil, date: date, calendar: Self.utcCalendar)
                == HeroArtworkCatalog.heroForDate(date, calendar: Self.utcCalendar)
        )
    }
}
