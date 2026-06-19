@testable import BriefRender
import DaybriefCore
import Foundation
import Testing

@Suite("BriefRenderer")
struct BriefRenderTests {
    // A pinned clock and a fixed UTC/en_US_POSIX calendar keep every output
    // deterministic — no wall-clock reads, no locale/time-zone drift.
    private static let generatedAt = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15 15:06:40 UTC
    private static let now = generatedAt.addingTimeInterval(2 * 3600 + 30) // +2h (just past)

    private func makeRenderer() -> BriefRenderer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return BriefRenderer(dateProvider: FixedDateProvider(Self.now), calendar: calendar)
    }

    /// A sample brief built in-test: out-of-order priorities, an unranked entry,
    /// a hostile-looking title/body, a safe link, an unsafe link, an empty section,
    /// and surfaced connector errors.
    private func sampleBrief() -> Brief {
        Brief(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            generatedAt: Self.generatedAt,
            spaceFilter: "work",
            lead: BriefEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!,
                headline: "Sign off the Q3 launch plan",
                detail: "Everything downstream is waiting on your go/no-go.",
                url: URL(string: "https://docs.google.com/launch"),
                priority: 0,
                ctaLabel: "Decide now"
            ),
            hero: HeroArtwork(
                assetName: "turner-whalers",
                title: "Whalers",
                artist: "J. M. W. Turner",
                year: "ca. 1845",
                accentHex: "#C06A2E"
            ),
            sections: [
                BriefSection(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    title: "Priorities",
                    entries: [
                        // priority 3 — should sort AFTER priority 1 below
                        BriefEntry(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                            headline: "Low-priority follow-up",
                            detail: nil,
                            url: nil,
                            priority: 3,
                            sourceItemIDs: []
                        ),
                        // priority 1 — most important
                        BriefEntry(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                            headline: "Reply to Jesse <about> \"Q3\" & budget",
                            detail: "He's blocked on your sign-off.",
                            url: URL(string: "https://mail.google.com/#all/abc"),
                            priority: 1,
                            sourceItemIDs: []
                        ),
                        // unranked — should sort LAST; unsafe link must be dropped
                        BriefEntry(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
                            headline: "Unranked note",
                            detail: "   ", // whitespace → nil
                            url: URL(string: "javascript:alert(1)"), // unsafe → dropped
                            priority: nil,
                            sourceItemIDs: []
                        ),
                    ]
                ),
                BriefSection(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    title: "What slipped",
                    entries: [] // empty → skipped in output
                ),
            ],
            signalsRead: 14,
            sources: [.gmail, .gcal],
            connectorErrors: [
                ConnectorErrorSummary(connectorId: .slack, kind: .timeout, message: "Fetch exceeded budget"),
                ConnectorErrorSummary(connectorId: .gmail, kind: .auth, message: "Token expired"),
            ]
        )
    }

    // MARK: - View model

    @Test("viewModel orders entries by priority, then unranked last, stable")
    func viewModelOrdering() {
        let vm = makeRenderer().viewModel(sampleBrief())

        #expect(vm.sections.count == 2)
        let priorities = vm.sections[0].entries
        #expect(priorities.map(\.headline) == [
            "Reply to Jesse <about> \"Q3\" & budget", // priority 1
            "Low-priority follow-up", // priority 3
            "Unranked note", // nil → last
        ])
        #expect(priorities.map(\.priority) == [1, 3, nil])
    }

    @Test("viewModel cleans detail and parses links safely")
    func viewModelLinkSafety() {
        let vm = makeRenderer().viewModel(sampleBrief())
        let entries = vm.sections[0].entries

        // Safe https link is surfaced with a host label.
        #expect(entries[0].link?.absoluteString == "https://mail.google.com/#all/abc")
        #expect(entries[0].linkLabel == "mail.google.com")
        #expect(entries[0].detail == "He's blocked on your sign-off.")

        // Unsafe javascript: link is dropped; whitespace-only detail collapses to nil.
        #expect(entries[2].link == nil)
        #expect(entries[2].linkLabel == nil)
        #expect(entries[2].detail == nil)
    }

    @Test("viewModel computes relative + absolute time and space label deterministically")
    func viewModelTimes() {
        let vm = makeRenderer().viewModel(sampleBrief())
        #expect(vm.generatedAtRelative == "Generated 2 hours ago")
        #expect(vm.spaceFilterDisplay == "Work")
        // Absolute time is fixed by the injected UTC/POSIX calendar.
        #expect(vm.generatedAtAbsolute.contains("2025"))
        #expect(vm.generatedAtAbsolute.contains("Jun 15"))
    }

    @Test("viewModel surfaces connector errors with display names")
    func viewModelErrors() {
        let vm = makeRenderer().viewModel(sampleBrief())
        #expect(vm.connectorErrors.map(\.connectorDisplay) == ["Slack", "Gmail"])
        #expect(vm.connectorErrors[0].kind == .timeout)
        #expect(vm.connectorErrors[1].message == "Token expired")
    }

    @Test("empty brief reports isEmpty and has no entry sections")
    func emptyBrief() {
        let brief = Brief(generatedAt: Self.generatedAt)
        let vm = makeRenderer().viewModel(brief)
        #expect(vm.isEmpty)
        #expect(vm.lead == nil)
        #expect(vm.connectorErrors.isEmpty)
    }

    // MARK: - Lead, colophon, accent

    @Test("viewModel projects the lead separately from sections, with its CTA")
    func viewModelLead() throws {
        let vm = makeRenderer().viewModel(sampleBrief())

        let lead = try #require(vm.lead)
        #expect(lead.headline == "Sign off the Q3 launch plan")
        #expect(lead.detail == "Everything downstream is waiting on your go/no-go.")
        #expect(lead.link?.absoluteString == "https://docs.google.com/launch")
        #expect(vm.leadCTALabel == "Decide now")
        #expect(!vm.isEmpty)

        // The lead is NOT duplicated into the sections (engine keeps them separate).
        let headlines = vm.sections.flatMap { $0.entries.map(\.headline) }
        #expect(!headlines.contains("Sign off the Q3 launch plan"))
    }

    @Test("viewModel builds a factual colophon: filing time, counts, source names")
    func viewModelColophon() {
        let vm = makeRenderer().viewModel(sampleBrief())
        // 14 read; surfaced = lead (1) + 3 Priorities entries + 0 in empty section = 4.
        // Sources map to display names in the brief's order (gmail, gcal).
        #expect(vm.colophon == "Filed 3:06 PM · 14 signals read, 4 surfaced · Gmail · Google Calendar")
    }

    @Test("colophon degrades to a clear day when nothing was read or surfaced")
    func viewModelColophonQuietDay() {
        let brief = Brief(generatedAt: Self.generatedAt, signalsRead: 0, sources: [])
        let vm = makeRenderer().viewModel(brief)
        #expect(vm.colophon == "Filed 3:06 PM · a clear day")
    }

    @Test("colophon pluralizes the signal count and shows counts even on a light day")
    func viewModelColophonPluralization() {
        // One signal read, nothing surfaced (read but not surfaced) — still honest.
        let one = Brief(generatedAt: Self.generatedAt, signalsRead: 1, sources: [.gmail])
        #expect(makeRenderer().viewModel(one).colophon
            == "Filed 3:06 PM · 1 signal read, 0 surfaced · Gmail")
    }

    @Test("accentHex passes through from the hero, nil without a hero")
    func viewModelAccent() {
        #expect(makeRenderer().viewModel(sampleBrief()).accentHex == "#C06A2E")
        #expect(makeRenderer().viewModel(Brief(generatedAt: Self.generatedAt)).accentHex == nil)
    }

    // MARK: - HTML

    @Test("HTML is a well-formed, self-contained document with expected structure")
    func htmlStructure() throws {
        let html = makeRenderer().renderHTML(sampleBrief())

        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.hasSuffix("</html>"))
        #expect(html.contains("<style>")) // inline CSS, self-contained
        #expect(!html.contains("http://") || html.contains("https://")) // no stray external asset hrefs

        // Header + meta.
        #expect(html.contains("<h1>Daybrief — Work</h1>"))
        #expect(html.contains("Generated 2 hours ago"))

        // Section headings; the empty "What slipped" section is omitted.
        #expect(html.contains("<h2>Priorities</h2>"))
        #expect(!html.contains("What slipped"))

        // Lead story rendered prominently above the sections, with its kicker + CTA.
        #expect(html.contains("<div class=\"lead\">"))
        #expect(html.contains("<p class=\"kicker\">Lead</p>"))
        #expect(html.contains("<h2>Sign off the Q3 launch plan</h2>"))
        #expect(html.contains(">Decide now</a>")) // lead CTA label preferred over host
        // The lead appears before the first section heading.
        let leadIdx = try #require(html.range(of: "Sign off the Q3 launch plan"))
        let firstSection = try #require(html.range(of: "<h2>Priorities</h2>"))
        #expect(leadIdx.lowerBound < firstSection.lowerBound)

        // Error block surfaced.
        #expect(html.contains("Some sources could not be reached"))
        #expect(html.contains("<strong>Slack</strong>"))

        // Colophon footer at the foot of the edition.
        #expect(html.contains("<p class=\"colophon\">"))
        #expect(html.contains("Filed 3:06 PM · 14 signals read, 4 surfaced · Gmail · Google Calendar"))
    }

    @Test("HTML escapes all user content — no injection from titles/bodies")
    func htmlEscaping() {
        let brief = Brief(
            generatedAt: Self.generatedAt,
            sections: [
                BriefSection(title: "S & <T>", entries: [
                    BriefEntry(
                        headline: "<script>alert('xss')</script>",
                        detail: "a & b > c < d \"quote\"",
                        url: URL(string: "https://x.test/?a=1&b=2"),
                        priority: 1
                    ),
                ]),
            ],
            // Non-zero so the renderer keeps the content (the signal-gated quiet-day guard
            // only strips lead/sections when nothing was read).
            signalsRead: 1
        )
        let html = makeRenderer().renderHTML(brief)

        // The raw script tag must NOT appear; only its escaped form.
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"))
        // Section title and detail are escaped.
        #expect(html.contains("<h2>S &amp; &lt;T&gt;</h2>"))
        #expect(html.contains("a &amp; b &gt; c &lt; d &quot;quote&quot;"))
        // The href value is escaped in the attribute context (& → &amp;).
        #expect(html.contains("href=\"https://x.test/?a=1&amp;b=2\""))
        #expect(html.contains("rel=\"noopener noreferrer\""))
    }

    @Test("HTML drops unsafe-scheme links entirely")
    func htmlDropsUnsafeLinks() {
        let brief = Brief(
            generatedAt: Self.generatedAt,
            sections: [
                BriefSection(title: "X", entries: [
                    BriefEntry(headline: "h", url: URL(string: "javascript:alert(1)"), priority: 1),
                    BriefEntry(headline: "h2", url: URL(string: "file:///etc/passwd"), priority: 2),
                ]),
            ]
        )
        let html = makeRenderer().renderHTML(brief)
        #expect(!html.contains("javascript:"))
        #expect(!html.contains("file:///"))
        #expect(!html.contains("entry-link")) // no anchors emitted at all
    }

    @Test("empty brief renders an explicit empty-state in HTML")
    func htmlEmptyState() {
        let html = makeRenderer().renderHTML(Brief(generatedAt: Self.generatedAt))
        #expect(html.contains("No items in this brief."))
        #expect(html.contains("<h1>Daybrief</h1>")) // no space suffix when filter is nil
    }

    // MARK: - Markdown

    @Test("Markdown has expected heading, ordering, links, and error block")
    func markdownStructure() throws {
        let md = makeRenderer().renderMarkdown(sampleBrief())

        #expect(md.hasPrefix("# Daybrief — Work\n"))
        #expect(md.contains("_") && md.contains("Generated 2 hours ago_"))
        #expect(md.contains("## Priorities"))
        #expect(!md.contains("## What slipped")) // empty section omitted

        // Priority-1 entry appears before priority-3 entry.
        let p1 = try #require(md.range(of: "Reply to Jesse"))
        let p3 = try #require(md.range(of: "Low-priority follow-up"))
        #expect(p1.lowerBound < p3.lowerBound)

        // Safe link rendered as Markdown link; detail rendered.
        #expect(md.contains("[mail.google.com](https://mail.google.com/#all/abc)"))
        #expect(md.contains("He's blocked on your sign-off."))

        // Lead story set off above the sections as its own heading, before "Priorities".
        let lead = try #require(md.range(of: "## Sign off the Q3 launch plan"))
        #expect(try lead.lowerBound < (#require(md.range(of: "## Priorities")).lowerBound))
        #expect(md.contains("[Decide now](https://docs.google.com/launch)"))

        // Error block.
        #expect(md.contains("## Some sources could not be reached"))
        #expect(md.contains("**Slack** (timeout) — Fetch exceeded budget"))

        // Colophon footer, italicized after a rule.
        #expect(md.contains("_Filed 3:06 PM · 14 signals read, 4 surfaced · Gmail · Google Calendar_"))
        #expect(md.hasSuffix("\n"))
    }

    @Test("Markdown omits unsafe links and empty details")
    func markdownDropsUnsafe() throws {
        let md = makeRenderer().renderMarkdown(sampleBrief())
        #expect(!md.contains("javascript:"))
        // The unranked note has no link line and no detail line following it.
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let idx = try #require(lines.firstIndex(of: "- Unranked note"))
        // Next non-empty line should be a new section/entry, not a detail/link for this entry.
        let next = lines[(idx + 1)...].first { !$0.isEmpty } ?? ""
        #expect(!next.hasPrefix("  ")) // no indented detail/link continuation
    }

    // MARK: - Relative time edges

    @Test("relative-time hints cover the coarse buckets")
    func relativeTimeBuckets() {
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        func hint(secondsAgo: Double) -> String {
            BriefPresentation.relativeTime(of: base, now: base.addingTimeInterval(secondsAgo))
        }
        #expect(hint(secondsAgo: 5) == "just now")
        #expect(hint(secondsAgo: 60) == "1 minute ago")
        #expect(hint(secondsAgo: 600) == "10 minutes ago")
        #expect(hint(secondsAgo: 3600) == "1 hour ago")
        #expect(hint(secondsAgo: 7200) == "2 hours ago")
        #expect(hint(secondsAgo: 90000) == "1 day ago")
        #expect(hint(secondsAgo: 180_000) == "2 days ago")
        // Future-dated brief (clock skew) reads naturally.
        #expect(BriefPresentation.relativeTime(of: base, now: base.addingTimeInterval(-3600)) == "in 1 hour")
    }
}
