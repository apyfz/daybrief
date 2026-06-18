import DaybriefCore
import Foundation
import LLMKit
@testable import Pipeline
import Testing

@Suite("Synthesizer mapping")
struct SynthesizerTests {
    /// 2026-06-17 is a Wednesday — pin the clock so the masthead + hero are stable.
    private static func wednesday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 17
        components.hour = 5
        components.minute = 32
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let cannedJSON = """
    {
      "masthead": "The Wednesday Brief",
      "lede": "Nothing on the calendar today or tomorrow. Two full days of heads-down time.",
      "sections": [
        {
          "title": "Push your work forward",
          "entries": [
            {
              "headline": "Draft the revised Cashfeed website copy",
              "detail": "Dennis laid out a clear PAY / MANAGE / OPTIMIZE structure yesterday.",
              "url": "https://example.com/thread/1",
              "priority": 1,
              "ctaLabel": "Let's do it"
            }
          ]
        }
      ]
    }
    """

    private func makeSynthesizer(
        synthesisTimeout: Duration = Synthesizer.defaultSynthesisTimeout
    ) -> Synthesizer {
        Synthesizer(
            dateProvider: FixedDateProvider(Self.wednesday()),
            calendar: Self.utcCalendar,
            synthesisTimeout: synthesisTimeout
        )
    }

    @Test("maps a canned SynthesizedBrief into a Brief with masthead, lede, hero, sections")
    func mapsCannedJSONIntoBrief() async throws {
        let adapter = StubModelAdapter(structuredResponses: [Self.cannedJSON])

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model"
        )

        #expect(brief.masthead == "The Wednesday Brief")
        #expect(brief.lede.hasPrefix("Nothing on the calendar"))
        #expect(brief.generatedAt == Self.wednesday())

        // Hero is assigned deterministically by date and matches the catalog selector.
        let expectedHero = HeroArtworkCatalog.heroForDate(Self.wednesday(), calendar: Self.utcCalendar)
        #expect(brief.hero == expectedHero)
        #expect(brief.hero != nil)

        // Sections + entries map through, including url / priority / ctaLabel.
        #expect(brief.sections.count == 1)
        let section = try #require(brief.sections.first)
        #expect(section.title == "Push your work forward")
        let entry = try #require(section.entries.first)
        #expect(entry.headline == "Draft the revised Cashfeed website copy")
        #expect(entry.priority == 1)
        #expect(entry.ctaLabel == "Let's do it")
        #expect(entry.url == URL(string: "https://example.com/thread/1"))
    }

    /// Canned JSON exercising the editorial extensions: a mood + a dedicated lead
    /// story alongside the sections.
    private static let cannedWithMoodAndLead = """
    {
      "masthead": "The Wednesday Brief",
      "lede": "A launch dominates the day.",
      "mood": "eventful",
      "lead": {
        "headline": "Ship the Cashfeed launch",
        "detail": "Everything is staged; Dennis signs off at 9.",
        "url": "https://example.com/launch",
        "priority": 0,
        "ctaLabel": "Let's ship it"
      },
      "sections": [
        {
          "title": "On the calendar",
          "entries": [
            { "headline": "Standup at 10:00", "detail": null, "url": null, "priority": null, "ctaLabel": null }
          ]
        }
      ]
    }
    """

    @Test("maps mood, the lead story, and a tone-matched hero")
    func mapsMoodLeadAndTonedHero() async throws {
        let adapter = StubModelAdapter(structuredResponses: [Self.cannedWithMoodAndLead])

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model"
        )

        // Mood maps onto the taxonomy.
        #expect(brief.mood == .eventful)

        // The lead story is its own entry, separate from the sections.
        let lead = try #require(brief.lead)
        #expect(lead.headline == "Ship the Cashfeed launch")
        #expect(lead.priority == 0)
        #expect(lead.ctaLabel == "Let's ship it")
        #expect(lead.url == URL(string: "https://example.com/launch"))
        // The lead is NOT duplicated into the sections.
        let sectionHeadlines = brief.sections.flatMap { $0.entries.map(\.headline) }
        #expect(!sectionHeadlines.contains(lead.headline))
        #expect(brief.sections.first?.title == "On the calendar")

        // The hero is the tone-matched pick for the mood (not the plain by-date pick).
        let expected = HeroArtworkCatalog.heroForMood(.eventful, date: Self.wednesday(), calendar: Self.utcCalendar)
        #expect(brief.hero == expected)
        // Its accent is sampled from the painting (set for every catalog entry).
        #expect(brief.hero?.accentHex != nil)
    }

    @Test("an unknown mood string maps to the steady default and lead may be null")
    func unknownMoodFallsBackAndNullLead() async throws {
        let json = """
        {
          "masthead": "The Wednesday Brief",
          "lede": "Quiet.",
          "mood": "frantic",
          "lead": null,
          "sections": []
        }
        """
        let adapter = StubModelAdapter(structuredResponses: [json])

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model"
        )

        #expect(brief.mood == .steady)
        #expect(brief.lead == nil)
    }

    @Test("provenance: signalsRead + sources are computed from the items when not supplied")
    func provenanceDerivedFromItems() async throws {
        let adapter = StubModelAdapter(structuredResponses: [Self.cannedJSON])
        let now = Self.wednesday()
        let items = [
            BriefItem(source: .gmail, account: "a", space: "work", type: .email, title: "x", timestamp: now),
            BriefItem(source: .gmail, account: "a", space: "work", type: .email, title: "y", timestamp: now),
            BriefItem(source: .gcal, account: "b", space: "work", type: .event, title: "z", timestamp: now),
        ]

        let brief = try await makeSynthesizer().synthesize(
            items: items,
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model"
        )

        #expect(brief.signalsRead == 3)
        // Distinct sources, in first-seen order.
        #expect(brief.sources == [.gmail, .gcal])
    }

    @Test("provenance: explicit signalsRead + sources override the item-derived values")
    func provenanceExplicitOverride() async throws {
        let adapter = StubModelAdapter(structuredResponses: [Self.cannedJSON])

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model",
            signalsRead: 14,
            sources: [.gmail, .slack]
        )

        #expect(brief.signalsRead == 14)
        #expect(brief.sources == [.gmail, .slack])
    }

    @Test("falls back to a weekday masthead when the model omits one")
    func fallsBackToWeekdayMasthead() async throws {
        let blankMasthead = """
        { "masthead": "  ", "lede": "x", "sections": [] }
        """
        let adapter = StubModelAdapter(structuredResponses: [blankMasthead])

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model"
        )

        #expect(brief.masthead == "The Wednesday Brief")
    }

    @Test("attaches the supplied connector errors and space filter")
    func attachesMetadata() async throws {
        let adapter = StubModelAdapter(structuredResponses: [Self.cannedJSON])
        let errors = [
            ConnectorErrorSummary(connectorId: .slack, kind: .timeout, message: "slow"),
        ]

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model",
            spaceFilter: "work",
            connectorErrors: errors
        )

        #expect(brief.spaceFilter == "work")
        #expect(brief.connectorErrors == errors)
    }

    @Test("a hung model call times out as synthesisFailed instead of hanging the brief")
    func slowModelTimesOut() async throws {
        // The adapter would sleep for a full minute; the injected budget is tiny, so
        // the timeout race wins and the synthesizer surfaces a clean failure rather
        // than stalling. A real ContinuousClock makes the race genuine (the adapter
        // actually sleeps), but the budget is small enough to keep the test fast.
        let adapter = SlowModelAdapter(delay: .seconds(60))
        let synthesizer = makeSynthesizer(synthesisTimeout: .milliseconds(20))

        do {
            _ = try await synthesizer.synthesize(
                items: [],
                template: .bundledDefault,
                adapter: adapter,
                model: "stub/model"
            )
            Issue.record("expected synthesize to throw on timeout instead of hanging")
        } catch let error as PipelineError {
            // The timeout must surface as a clean synthesis failure, not a hang.
            guard case .synthesisFailed = error else {
                Issue.record("expected .synthesisFailed, got \(error)")
                return
            }
        }
    }

    @Test("null optional fields decode to nil entry fields")
    func nullOptionalsDecodeToNil() async throws {
        let nulls = """
        {
          "masthead": "The Wednesday Brief",
          "lede": "Quiet.",
          "sections": [
            { "title": "Notes", "entries": [
              { "headline": "Just a note", "detail": null, "url": null, "priority": null, "ctaLabel": null }
            ]}
          ]
        }
        """
        let adapter = StubModelAdapter(structuredResponses: [nulls])

        let brief = try await makeSynthesizer().synthesize(
            items: [],
            template: .bundledDefault,
            adapter: adapter,
            model: "stub/model"
        )

        let entry = try #require(brief.sections.first?.entries.first)
        #expect(entry.detail == nil)
        #expect(entry.url == nil)
        #expect(entry.priority == nil)
        #expect(entry.ctaLabel == nil)
    }

    @Test("the strict schema sets additionalProperties:false and requires every property")
    func schemaIsStrict() throws {
        let schema = Synthesizer.schema.schema
        #expect(schema["additionalProperties"]?.bool == false)
        let required = try #require(schema["required"]?.array)
        #expect(Set(required.compactMap(\.string)) == ["masthead", "lede", "mood", "lead", "sections"])

        // mood is an enum string constrained to the BriefMood raw values.
        let moodEnum = try #require(schema["properties"]?["mood"]?["enum"]?.array)
        #expect(Set(moodEnum.compactMap(\.string)) == Set(BriefMood.allCases.map(\.rawValue)))

        // The lead is a nullable entry object requiring the same five properties.
        let leadSchema = try #require(schema["properties"]?["lead"])
        let leadType = try #require(leadSchema["type"]?.array)
        #expect(Set(leadType.compactMap(\.string)) == ["object", "null"])
        let leadRequired = try #require(leadSchema["required"]?.array)
        #expect(Set(leadRequired.compactMap(\.string)) == ["headline", "detail", "url", "priority", "ctaLabel"])

        // The entry object must require all five properties (optionals as nullable).
        let entrySchema = try #require(
            schema["properties"]?["sections"]?["items"]?["properties"]?["entries"]?["items"]
        )
        #expect(entrySchema["additionalProperties"]?.bool == false)
        let entryRequired = try #require(entrySchema["required"]?.array)
        #expect(Set(entryRequired.compactMap(\.string)) == ["headline", "detail", "url", "priority", "ctaLabel"])

        // detail is a nullable string union.
        let detailType = try #require(entrySchema["properties"]?["detail"]?["type"]?.array)
        #expect(Set(detailType.compactMap(\.string)) == ["string", "null"])
    }
}
