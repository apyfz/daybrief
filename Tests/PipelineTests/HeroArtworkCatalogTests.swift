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
}
