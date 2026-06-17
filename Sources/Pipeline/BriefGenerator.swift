import ConnectorKit
import DaybriefCore
import Foundation
import LLMKit
import os

/// The pipeline orchestrator: fetch → normalize → synthesize → assemble → persist.
///
/// `BriefGenerator` runs each enabled connector's `fetch` **concurrently** in a
/// `withThrowingTaskGroup`, where every child task races the fetch against the
/// connector's ``ConnectorKit/Connector/fetchTimeout`` and maps *every* result —
/// success, timeout, or throw (honoring cancellation) — into a non-throwing
/// ``ConnectorOutcome``. One dead or slow connector therefore can never throw out
/// of the group or kill the brief (design §6); the orchestrator always assembles a
/// partial brief plus a surfaced ``DaybriefCore/ConnectorErrorSummary`` list.
///
/// It then calls the ``Synthesizer`` (which owns the LLM call + structured-output
/// repair), and persists the result through the injected ``BriefSink``.
///
/// Library code: `nonisolated`, `Sendable`, honors cooperative cancellation.
public struct BriefGenerator: Sendable {
    private let synthesizer: Synthesizer
    private let dateProvider: any DateProvider
    private let clock: any Clock<Duration>
    private static let logger = Logger(subsystem: "co.daybrief.pipeline", category: "BriefGenerator")

    /// Creates a brief generator.
    ///
    /// - Parameters:
    ///   - synthesizer: The synthesizer (defaults to a fresh one over `dateProvider`).
    ///   - dateProvider: Source of "now" for the fetch window + brief metadata.
    ///   - clock: The clock used for the per-connector timeout race (injectable so
    ///     tests can drive timeouts deterministically; defaults to `ContinuousClock`).
    public init(
        synthesizer: Synthesizer? = nil,
        dateProvider: any DateProvider = SystemDateProvider(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.dateProvider = dateProvider
        self.synthesizer = synthesizer ?? Synthesizer(dateProvider: dateProvider)
        self.clock = clock
    }

    /// Generates a brief from the enabled connectors in `registry`.
    ///
    /// - Parameters:
    ///   - registry: The connector registry; only enabled connectors are fetched.
    ///   - accountsByConnector: The enabled accounts to fetch for each connector id.
    ///     Connectors with no accounts are skipped (nothing to fetch).
    ///   - tokenProvider: Supplies per-account access tokens to the connectors.
    ///   - template: The voice/layout prompt template.
    ///   - adapter: The model backend.
    ///   - model: The provider model id to synthesize with.
    ///   - spaceFilter: The space to filter the brief to, or `nil` for all spaces.
    ///   - fetchWindow: The since…until window to fetch over (defaults to today
    ///     00:00 → tomorrow 23:59 local, per design §7).
    ///   - sink: Where to persist the finished brief, or `nil` to skip persistence
    ///     (the caller persists separately).
    /// - Returns: The assembled ``DaybriefCore/Brief`` (partial if connectors failed).
    /// - Throws: ``PipelineError/synthesisFailed(reason:)`` /
    ///   ``PipelineError/persistenceFailed(reason:)``, or `CancellationError`.
    ///   A *connector* failure never throws — it is folded into the brief.
    @discardableResult
    public func generate(
        registry: ConnectorRegistry,
        accountsByConnector: [ConnectorID: [Account]],
        tokenProvider: any TokenProvider,
        template: PromptTemplate,
        adapter: any ModelAdapter,
        model: String,
        spaceFilter: String? = nil,
        fetchWindow: (since: Date, until: Date)? = nil,
        sink: (any BriefSink)? = nil
    ) async throws -> Brief {
        let now = dateProvider.now()
        let window = fetchWindow ?? Self.defaultWindow(now: now)

        // 1. Fetch + normalize every enabled connector concurrently; collect outcomes.
        let outcomes = await collectOutcomes(
            connectors: registry.enabledConnectors,
            accountsByConnector: accountsByConnector,
            tokenProvider: tokenProvider,
            since: window.since,
            until: window.until
        )

        // Cooperative cancellation: if the whole generation was cancelled, abort
        // before spending a model call.
        try Task.checkCancellation()

        // 2. Partition outcomes into items + surfaced errors. A dead connector is
        //    surfaced, never fatal.
        let items = outcomes.flatMap(\.items)
        let connectorErrors = outcomes.compactMap(\.errorSummary)
        if !connectorErrors.isEmpty {
            Self.logger.notice("Assembling partial brief: \(connectorErrors.count, privacy: .public) connector(s) failed")
        }

        // Colophon provenance, computed at assembly (never from the model):
        // - signalsRead is the number of normalized items we actually read.
        // - sources is the distinct connectors that produced items, in first-seen
        //   order; when nothing was produced (a quiet day), fall back to the
        //   connectors that were actually fetched (enabled + had accounts) so the
        //   colophon still names where we looked.
        let signalsRead = items.count
        let fetchedSources = Self.fetchedConnectorIDs(
            connectors: registry.enabledConnectors,
            accountsByConnector: accountsByConnector
        )
        let sources = Synthesizer.distinctSources(of: items).isEmpty
            ? fetchedSources
            : Synthesizer.distinctSources(of: items)

        // 3. Synthesize the editorial brief (LLM + repair backstop).
        let brief = try await synthesizer.synthesize(
            items: items,
            template: template,
            adapter: adapter,
            model: model,
            spaceFilter: spaceFilter,
            connectorErrors: connectorErrors,
            signalsRead: signalsRead,
            sources: sources
        )

        // 4. Persist (best path) — failures here are pipeline errors, not connector errors.
        if let sink {
            try await sink.persist(brief, items: items)
        }

        return brief
    }

    // MARK: - Concurrent fetch with per-connector timeout race

    /// Runs every connector's fetch+normalize concurrently, each raced against its
    /// own ``ConnectorKit/Connector/fetchTimeout``, returning a non-throwing
    /// ``ConnectorOutcome`` per connector. The group itself never throws.
    private func collectOutcomes(
        connectors: [any Connector],
        accountsByConnector: [ConnectorID: [Account]],
        tokenProvider: any TokenProvider,
        since: Date,
        until: Date
    ) async -> [ConnectorOutcome] {
        // Capture the value-typed dependencies the child tasks need so the closure
        // stays Sendable under strict concurrency.
        let synthClock = clock
        let provider = tokenProvider

        return await withTaskGroup(of: ConnectorOutcome.self) { group in
            for connector in connectors {
                let id = connector.id
                let accounts = accountsByConnector[id] ?? []
                // Nothing to fetch for a connector with no enabled accounts.
                guard !accounts.isEmpty else { continue }
                let request = FetchRequest(accounts: accounts, since: since, until: until)

                group.addTask {
                    await Self.runConnector(
                        connector,
                        request: request,
                        tokenProvider: provider,
                        timeout: connector.fetchTimeout,
                        clock: synthClock
                    )
                }
            }

            var results: [ConnectorOutcome] = []
            for await outcome in group {
                results.append(outcome)
            }
            return results
        }
    }

    /// Runs one connector's fetch raced against its timeout, then normalizes,
    /// mapping every outcome into a ``ConnectorOutcome``. Never throws.
    ///
    /// The token provider is consulted up front (so an auth failure surfaces as an
    /// auth error before the fetch), then the connector's own `fetch` runs inside
    /// the timeout race. The race uses a nested task group: one child performs the
    /// fetch, a sibling sleeps for the budget; whichever finishes first wins and the
    /// other is cancelled. The connector honors cooperative cancellation per the
    /// `Connector` contract.
    static func runConnector(
        _ connector: any Connector,
        request: FetchRequest,
        tokenProvider: any TokenProvider,
        timeout: Duration,
        clock: any Clock<Duration>
    ) async -> ConnectorOutcome {
        let id = connector.id

        // Pre-resolve tokens so a missing/expired token surfaces as an auth error
        // rather than a connector-internal throw of indeterminate kind. Connectors
        // are also handed the provider, but resolving here gives a clean auth signal.
        do {
            for account in request.accounts {
                _ = try await tokenProvider.accessToken(for: account)
            }
        } catch is CancellationError {
            return .failed(id, ConnectorError.timedOut.summary(connectorId: id))
        } catch {
            let summary = ConnectorErrorSummary(
                connectorId: id,
                kind: .auth,
                message: "Could not get a valid token for this account."
            )
            return .failed(id, summary)
        }

        do {
            let raw = try await withTimeout(timeout, clock: clock) {
                try await connector.fetch(request)
            }
            // Normalize is pure + synchronous per contract.
            let items = connector.normalize(raw)
            // Backfill each item's Space from the originating account: connectors
            // can't know spaces (normalize has no Account access), so they emit a
            // placeholder that we overwrite by matching BriefItem.account == Account.label.
            let spaceByLabel = Dictionary(
                request.accounts.map { ($0.label, $0.spaceKey) },
                uniquingKeysWith: { first, _ in first }
            )
            let filed = items.map { item in
                spaceByLabel[item.account].map(item.settingSpace) ?? item
            }
            return .success(filed)
        } catch is TimeoutError {
            return .timedOut(id)
        } catch is CancellationError {
            // The orchestrator (not the timeout) cancelled us; surface as a timeout-class
            // error so it is visible without being fatal.
            return .timedOut(id)
        } catch let error as ConnectorError {
            if case .timedOut = error { return .timedOut(id) }
            return .failed(id, error.summary(connectorId: id))
        } catch let error as URLError where error.code == .cancelled {
            return .timedOut(id)
        } catch let error as URLError {
            let summary = ConnectorErrorSummary(
                connectorId: id,
                kind: .network,
                message: "Network error (\(error.code.rawValue))."
            )
            return .failed(id, summary)
        } catch {
            let summary = ConnectorErrorSummary(
                connectorId: id,
                kind: .other,
                message: "The connector failed unexpectedly."
            )
            return .failed(id, summary)
        }
    }

    // MARK: - Provenance

    /// The ids of the connectors that were actually fetched — enabled *and* with at
    /// least one account to fetch — in registration order. Used as the colophon's
    /// source list on a quiet day that produced no items.
    static func fetchedConnectorIDs(
        connectors: [any Connector],
        accountsByConnector: [ConnectorID: [Account]]
    ) -> [ConnectorID] {
        connectors
            .map(\.id)
            .filter { !(accountsByConnector[$0] ?? []).isEmpty }
    }

    // MARK: - Fetch window

    /// The default fetch window: local today 00:00 → tomorrow 23:59 (design §7).
    static func defaultWindow(now: Date, calendar: Calendar = .current) -> (since: Date, until: Date) {
        let startOfToday = calendar.startOfDay(for: now)
        // End of tomorrow = start of (today + 2 days) minus one second.
        let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now
        let endOfTomorrow = startOfDayAfterTomorrow.addingTimeInterval(-1)
        return (since: startOfToday, until: endOfTomorrow)
    }
}
