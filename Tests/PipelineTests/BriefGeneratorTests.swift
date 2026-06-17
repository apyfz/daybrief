import ConnectorKit
import DaybriefCore
import Foundation
import LLMKit
@testable import Pipeline
import Testing

@Suite("BriefGenerator partial-brief assembly")
struct BriefGeneratorTests {
    /// A canned model response shaped like ``SynthesizedBrief`` so synthesis always
    /// succeeds and the test can focus on connector-outcome assembly.
    private static let cannedBriefJSON = """
    {
      "masthead": "The Monday Brief",
      "lede": "A calm start to the week.",
      "sections": [
        {
          "title": "Push your work forward",
          "entries": [
            { "headline": "Draft the proposal", "detail": "Dennis asked for it.", "url": null, "priority": 1, "ctaLabel": "Let's do it" }
          ]
        }
      ]
    }
    """

    private func makeAdapter() -> StubModelAdapter {
        StubModelAdapter(structuredResponses: [Self.cannedBriefJSON])
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000) // a deterministic instant

    private func makeGenerator() -> BriefGenerator {
        BriefGenerator(
            synthesizer: Synthesizer(dateProvider: FixedDateProvider(fixedNow)),
            dateProvider: FixedDateProvider(fixedNow),
            clock: ContinuousClock()
        )
    }

    @Test("a single dead connector never kills the brief; its error is surfaced")
    func deadConnectorIsSurfacedNotFatal() async throws {
        let good = StubConnector.succeeding(id: "good", title: "Hello")
        let dead = StubConnector(id: "dead", behavior: .throwError(.network(statusCode: 500, reason: "boom")))

        var registry = ConnectorRegistry()
        registry.register(good)
        registry.register(dead)

        let accounts: [ConnectorID: [Account]] = [
            "good": [TestAccounts.one(connectorId: "good")],
            "dead": [TestAccounts.one(connectorId: "dead")],
        ]

        let brief = try await makeGenerator().generate(
            registry: registry,
            accountsByConnector: accounts,
            tokenProvider: StaticTokenProvider(token: "t"),
            template: .bundledDefault,
            adapter: makeAdapter(),
            model: "stub/model"
        )

        // The brief was produced (synthesis ran) and the dead connector is surfaced.
        #expect(brief.masthead == "The Monday Brief")
        #expect(brief.connectorErrors.count == 1)
        let summary = try #require(brief.connectorErrors.first)
        #expect(summary.connectorId == ConnectorID("dead"))
        #expect(summary.kind == .network)
    }

    @Test("a hung connector times out without blocking the brief")
    func hungConnectorTimesOut() async throws {
        let good = StubConnector.succeeding(id: "good", title: "Hello")
        // Hang far longer than its 50ms budget; the timeout race aborts it.
        let slow = StubConnector(
            id: "slow",
            behavior: .hang(for: .seconds(60)),
            fetchTimeout: .milliseconds(50)
        )

        var registry = ConnectorRegistry()
        registry.register(good)
        registry.register(slow)

        let accounts: [ConnectorID: [Account]] = [
            "good": [TestAccounts.one(connectorId: "good")],
            "slow": [TestAccounts.one(connectorId: "slow")],
        ]

        let brief = try await makeGenerator().generate(
            registry: registry,
            accountsByConnector: accounts,
            tokenProvider: StaticTokenProvider(token: "t"),
            template: .bundledDefault,
            adapter: makeAdapter(),
            model: "stub/model"
        )

        let summary = try #require(brief.connectorErrors.first { $0.connectorId == ConnectorID("slow") })
        #expect(summary.kind == .timeout)
        // The brief still assembled.
        #expect(brief.sections.count == 1)
    }

    @Test("all three outcomes — success, timeout, throw — fold into one partial brief")
    func mixedOutcomes() async throws {
        let ok = StubConnector.succeeding(id: "ok", title: "Item")
        let slow = StubConnector(id: "slow", behavior: .hang(for: .seconds(60)), fetchTimeout: .milliseconds(50))
        let bad = StubConnector(id: "bad", behavior: .throwError(.authFailed(reason: "expired")))

        var registry = ConnectorRegistry([ok, slow, bad])
        registry.setEnabled(true, for: "ok")

        let accounts: [ConnectorID: [Account]] = [
            "ok": [TestAccounts.one(connectorId: "ok")],
            "slow": [TestAccounts.one(connectorId: "slow")],
            "bad": [TestAccounts.one(connectorId: "bad")],
        ]

        let sink = SpyBriefSink()
        let brief = try await makeGenerator().generate(
            registry: registry,
            accountsByConnector: accounts,
            tokenProvider: StaticTokenProvider(token: "t"),
            template: .bundledDefault,
            adapter: makeAdapter(),
            model: "stub/model",
            sink: sink
        )

        // Two surfaced errors (timeout + auth), one success contributed an item.
        #expect(brief.connectorErrors.count == 2)
        let kinds = Set(brief.connectorErrors.map(\.kind))
        #expect(kinds == [.timeout, .auth])

        // The success path's normalized item was persisted with the brief.
        let persistedItems = await sink.persistedItems
        #expect(persistedItems.first?.count == 1)
        let persistedBriefs = await sink.persistedBriefs
        #expect(persistedBriefs.count == 1)
    }

    @Test("disabled connectors are not fetched")
    func disabledConnectorsSkipped() async throws {
        let enabled = StubConnector.succeeding(id: "enabled", title: "Yes")
        let disabled = StubConnector(id: "disabled", behavior: .throwError(.other(reason: "should not run")))

        var registry = ConnectorRegistry([enabled, disabled])
        registry.setEnabled(false, for: "disabled")

        let accounts: [ConnectorID: [Account]] = [
            "enabled": [TestAccounts.one(connectorId: "enabled")],
            "disabled": [TestAccounts.one(connectorId: "disabled")],
        ]

        let brief = try await makeGenerator().generate(
            registry: registry,
            accountsByConnector: accounts,
            tokenProvider: StaticTokenProvider(token: "t"),
            template: .bundledDefault,
            adapter: makeAdapter(),
            model: "stub/model"
        )

        // The disabled connector never ran, so no error was surfaced for it.
        #expect(brief.connectorErrors.isEmpty)
    }

    @Test("a missing token surfaces as an auth error, not a crash")
    func missingTokenSurfacesAsAuth() async throws {
        let connector = StubConnector.succeeding(id: "needstoken", title: "x")
        var registry = ConnectorRegistry()
        registry.register(connector)

        let accounts: [ConnectorID: [Account]] = [
            "needstoken": [TestAccounts.one(connectorId: "needstoken")],
        ]

        // A token provider with no token for this account.
        let emptyProvider = StaticTokenProvider(tokensByAccountID: [:])

        let brief = try await makeGenerator().generate(
            registry: registry,
            accountsByConnector: accounts,
            tokenProvider: emptyProvider,
            template: .bundledDefault,
            adapter: makeAdapter(),
            model: "stub/model"
        )

        let summary = try #require(brief.connectorErrors.first)
        #expect(summary.kind == .auth)
    }
}
