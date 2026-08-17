import DaybriefCore
import Foundation
import LLMKit

/// Turns normalized ``DaybriefCore/BriefItem``s into an editorial
/// ``DaybriefCore/Brief`` via a ``LLMKit/ModelAdapter``.
///
/// The synthesizer:
/// 1. builds the synthesis prompt (system + user) from the items and a
///    user-editable ``PromptTemplate``,
/// 2. defines the **strict** JSON schema for ``SynthesizedBrief`` (every object
///    sets `additionalProperties: false` and lists *all* properties in `required`,
///    optionals modeled as nullable — per design §8), and
/// 3. calls ``LLMKit/ModelAdapter/completeStructured(_:schema:as:)`` (which runs
///    the validate-and-repair backstop) and maps the result into a `Brief`,
///    assigning the id, `generatedAt`, `spaceFilter`, the deterministic hero, and
///    attaching the surfaced connector errors.
///
/// It does not fetch, persist, or schedule — ``BriefGenerator`` orchestrates those.
public struct Synthesizer: Sendable {
    private let dateProvider: any DateProvider
    private let calendar: Calendar
    private let synthesisTimeout: Duration
    private let clock: any Clock<Duration>

    /// The default budget for a single synthesis model call before it is abandoned.
    public static let defaultSynthesisTimeout: Duration = .seconds(120)

    /// Creates a synthesizer.
    ///
    /// - Parameters:
    ///   - dateProvider: Source of `generatedAt` and the weekday/hero date
    ///     (injectable for deterministic tests).
    ///   - calendar: Calendar used for weekday + hero selection (defaults to
    ///     `.current`).
    ///   - synthesisTimeout: The budget for the model call. A slow or hung provider
    ///     is abandoned after this and surfaced as
    ///     ``PipelineError/synthesisFailed(reason:)`` rather than stalling the whole
    ///     brief (defaults to ``defaultSynthesisTimeout``).
    ///   - clock: The clock used for the synthesis timeout race (injectable so tests
    ///     can drive timeouts deterministically; defaults to `ContinuousClock`).
    public init(
        dateProvider: any DateProvider = SystemDateProvider(),
        calendar: Calendar = .current,
        synthesisTimeout: Duration = Synthesizer.defaultSynthesisTimeout,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.synthesisTimeout = synthesisTimeout
        self.clock = clock
    }

    /// Synthesizes a brief.
    ///
    /// - Parameters:
    ///   - items: The normalized items to synthesize from (may be empty — the
    ///     prompt instructs the model to be honest about a quiet day).
    ///   - template: The voice/layout prompt template.
    ///   - adapter: The model backend.
    ///   - model: The provider model id to use.
    ///   - spaceFilter: The space this brief was filtered to, or `nil` for all.
    ///   - connectorErrors: Surfaced connector failures to attach to the brief.
    ///   - signalsRead: How many normalized signals were read, for the colophon's
    ///     provenance line (computed by the caller, defaults to `items.count`).
    ///   - sources: The distinct connectors that contributed, for the colophon
    ///     (computed by the caller; defaults to the distinct sources of `items`).
    /// - Returns: A fully-assembled ``DaybriefCore/Brief``.
    /// - Throws: ``PipelineError/synthesisFailed(reason:)`` if the model call
    ///   exceeds the synthesis budget, or if the call or repair layer otherwise
    ///   fails.
    public func synthesize(
        items: [BriefItem],
        template: PromptTemplate,
        adapter: any ModelAdapter,
        model: String,
        spaceFilter: String? = nil,
        connectorErrors: [ConnectorErrorSummary] = [],
        signalsRead: Int? = nil,
        sources: [ConnectorID]? = nil
    ) async throws -> Brief {
        let now = dateProvider.now()
        let weekday = Self.weekdayName(for: now, calendar: calendar)
        let input = makeInput(items: items, template: template, model: model, weekday: weekday)

        let synthesized: SynthesizedBrief
        do {
            // Bound the model call: a slow or hung provider is abandoned after the
            // budget so it can't stall the whole brief. `completeStructured` honors
            // cooperative cancellation, so the timeout sleeper winning the race tears
            // down the in-flight request.
            synthesized = try await withTimeout(synthesisTimeout, clock: clock) {
                try await adapter.completeStructured(
                    input,
                    schema: Self.schema,
                    as: SynthesizedBrief.self
                )
            }
        } catch is TimeoutError {
            throw PipelineError.synthesisFailed(
                reason: "the model did not respond within \(synthesisTimeout)"
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LLMError {
            throw PipelineError.synthesisFailed(reason: error.displayReason)
        } catch let error as URLError {
            // A raw network error reaching the model service — give it a human reason
            // instead of leaking "NSURLError".
            let reason: String
            switch error.code {
            case .timedOut:
                reason = "the AI service took too long to respond — try again, or pick a faster model"
            case .notConnectedToInternet:
                reason = "there's no internet connection"
            case .networkConnectionLost:
                reason = "the network connection dropped — try again"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                reason = "couldn't reach the AI service — check your connection"
            default:
                reason = "a network error reaching the AI service (code \(error.code.rawValue))"
            }
            throw PipelineError.synthesisFailed(reason: reason)
        } catch {
            throw PipelineError.synthesisFailed(reason: error.localizedDescription)
        }

        // Provenance for the colophon is computed at assembly, never by the model.
        // The caller may pass exact counts (it knows which connectors were enabled
        // and how it normalized); otherwise derive from the items we synthesized from.
        let resolvedSignalsRead = signalsRead ?? items.count
        let resolvedSources = sources ?? Self.distinctSources(of: items)

        return mapToBrief(
            synthesized,
            generatedAt: now,
            weekday: weekday,
            spaceFilter: spaceFilter,
            connectorErrors: connectorErrors,
            signalsRead: resolvedSignalsRead,
            sources: resolvedSources,
            items: items
        )
    }

    /// The distinct connector sources of `items`, in first-seen order (stable for the
    /// colophon rather than `Set`-ordered).
    static func distinctSources(of items: [BriefItem]) -> [ConnectorID] {
        var seen: Set<ConnectorID> = []
        var ordered: [ConnectorID] = []
        for item in items where seen.insert(item.source).inserted {
            ordered.append(item.source)
        }
        return ordered
    }

    // MARK: - Prompt assembly

    /// Builds the provider-neutral completion input from the items + template.
    func makeInput(
        items: [BriefItem],
        template: PromptTemplate,
        model: String,
        weekday: String
    ) -> CompletionInput {
        let user = """
        Today is \(weekday). Use the masthead "The \(weekday) Brief".

        \(template.renderNotes)

        STRUCTURE (required — this overrides any conflicting layout note above):
        - Write `summary`: the "Daybrief" overview, 2-4 calm sentences capturing the \
        whole day across ALL sources together (what matters, what's quiet). This is the \
        headline the reader sees first.
        - Then GROUP the items BY SOURCE into `sections`: exactly one section per source \
        that has items. Set each section's `source` to the connector id (gmail, gcal, \
        slack, notion) and `title` to its name (Gmail, Calendar, Slack, Notion). Never \
        mix sources in a section, and never create a section for a source with no items.
        - Within a section, write one entry per item (headline + a sentence of context), \
        ordered most-important first.
        - Every entry MUST list, in `sourceItemIDs`, the exact `id` of each item it was \
        written from. An item belongs to exactly one section — the one for its own \
        source — so never write the same item into two different sections.
        - SLACK is special: split it into TWO sections, both with source "slack". \
        Every Slack item carries an audience in its urgency hints — put the "for-you" \
        items (1:1 DMs and @-mentions, which usually owe a reply) in a section titled \
        "Slack — For you" with audience "for-you", and the "group" items (group DMs and \
        channel messages, which are ambient) in a section titled "Slack — Group" with \
        audience "group". \
        Never move an item between the two, and omit either section entirely when it \
        has no items. Summarize group traffic; do not list every message.
        - Set `audience` to "" for every non-Slack section.
        - Give an entry a `ctaLabel` ONLY when the reader has something to actually do \
        (reply, pay, review, decide). Anything you'd describe as routine, automated, \
        already handled, or "no action needed" MUST have `ctaLabel: null` — a button on \
        an FYI is noise that contradicts what the entry just said.
        - Keep `lede` to a single short kicker line.

        Here are the normalized items gathered from the reader's connected tools. \
        Each item lists its id, source, type, the people involved, its timestamp, \
        any urgency hints, and a short body where available. Synthesize the brief \
        from these — and only these — items.

        ITEMS
        \(Self.renderItems(items))
        """

        return CompletionInput(
            system: template.systemPrompt,
            messages: [.user(user)],
            model: model,
            temperature: 0.4
        )
    }

    /// Renders the items into a compact, model-readable digest. Bodies are
    /// included verbatim (snippets only in v0) so the model has real context.
    static func renderItems(_ items: [BriefItem]) -> String {
        guard !items.isEmpty else {
            return "(No items were gathered. The day may genuinely be quiet — say so honestly.)"
        }
        let formatter = ISO8601DateFormatter()
        return items.map { item in
            var lines = [
                "- id: \(item.id.uuidString)",
                "  source: \(item.source.rawValue)",
                "  account: \(item.account)",
                "  type: \(item.type.rawValue)",
                "  title: \(item.title)",
                "  timestamp: \(formatter.string(from: item.timestamp))",
            ]
            if !item.people.isEmpty {
                lines.append("  people: \(item.people.joined(separator: ", "))")
            }
            if !item.urgencyHints.isEmpty {
                lines.append("  urgency: \(item.urgencyHints.map(\.rawValue).joined(separator: ", "))")
            }
            if let url = item.url {
                lines.append("  url: \(url.absoluteString)")
            }
            if let body = item.body, !body.isEmpty {
                lines.append("  body: \(body)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")
    }

    /// The full weekday name (e.g. "Wednesday") for `date`, in `en_US_POSIX` so
    /// the masthead is locale-stable and matches the design's English wording.
    static func weekdayName(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    // MARK: - Mapping

    /// Maps the model DTO into a `Brief`, assigning all pipeline metadata.
    func mapToBrief(
        _ synthesized: SynthesizedBrief,
        generatedAt: Date,
        weekday: String,
        spaceFilter: String?,
        connectorErrors: [ConnectorErrorSummary],
        signalsRead: Int,
        sources: [ConnectorID],
        items: [BriefItem] = []
    ) -> Brief {
        // Trust the model's masthead when it followed the "The <Weekday> Brief"
        // instruction; otherwise fall back to the deterministic, correct form.
        let masthead = synthesized.masthead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "The \(weekday) Brief"
            : synthesized.masthead

        // The model emits a free-form mood string; map it onto the robust taxonomy
        // (unknown / blank → the neutral default) so the hero + accent are stable.
        let mood = BriefMood(rawValue: synthesized.mood.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? .default

        // Source-grouped: each section carries its connector so the UI can render a
        // per-source dropdown. An unknown/blank source maps to nil (rendered without an
        // icon). The lead story is retired in favor of the Daybrief summary card.
        let sections = Self.placedSections(of: synthesized, items: items)

        return Brief(
            generatedAt: generatedAt,
            spaceFilter: spaceFilter,
            masthead: masthead,
            lede: synthesized.lede,
            summary: synthesized.summary,
            lead: nil,
            mood: mood,
            // Tone-matched hero: pick by mood, deterministic by date, falling back to
            // the plain date pick when the mood has no matching painting.
            hero: HeroArtworkCatalog.heroForMood(mood, date: generatedAt, calendar: calendar),
            sections: sections,
            signalsRead: signalsRead,
            sources: sources,
            connectorErrors: connectorErrors
        )
    }

    /// Maps the model's sections into ``BriefSection``s, correcting where it filed each
    /// entry.
    ///
    /// The model groups by source in prose, and it *will* occasionally misfile — a Slack
    /// mention written into the Gmail section, sometimes duplicating an entry that is
    /// also filed correctly. Every entry cites the item ids it came from, so placement is
    /// checkable rather than a matter of trust: an entry is kept only in the section
    /// matching its items' own source (and, for Slack, their audience). A misfiled entry
    /// moves to the section it belongs in, or is dropped when no such section exists.
    ///
    /// Entries citing no resolvable item are left where the model put them — unverifiable
    /// is not the same as wrong, and dropping them would lose real content on a model that
    /// simply omitted the ids.
    static func placedSections(of synthesized: SynthesizedBrief, items: [BriefItem]) -> [BriefSection] {
        let itemsByID = Dictionary(items.map { ($0.id.uuidString.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        /// The (source, audience) bucket an entry's cited items agree on, or `nil` when
        /// nothing resolves.
        func bucket(of entry: SynthesizedBrief.Entry) -> Bucket? {
            let cited = entry.sourceItemIDs.compactMap { itemsByID[$0.trimmingCharacters(in: .whitespaces).lowercased()] }
            guard let first = cited.first else { return nil }
            return Bucket(source: first.source, audience: Self.audience(of: first))
        }

        // The bucket each of the model's sections declares it holds.
        let declared = synthesized.sections.map { section -> Bucket? in
            let raw = section.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            let source = ConnectorID(raw)
            let audience = section.audience.trimmingCharacters(in: .whitespacesAndNewlines)
            return Bucket(source: source, audience: source == .slack ? audience : "")
        }

        return synthesized.sections.enumerated().compactMap { index, section -> BriefSection? in
            let sectionBucket = declared[index]
            let entries = section.entries.filter { entry in
                guard let entryBucket = bucket(of: entry) else { return true } // unverifiable → leave be
                if entryBucket == sectionBucket { return true }
                // Misfiled: keep it here only when it has nowhere better to go, so the
                // content survives even if the grouping was wrong.
                return !declared.contains(entryBucket)
            }
            guard !entries.isEmpty else { return nil }
            return BriefSection(
                title: section.title,
                source: sectionBucket?.source,
                entries: entries.map(Self.mapEntry)
            )
        }
    }

    /// A section's identity for placement: which connector, and for Slack which half.
    struct Bucket: Equatable {
        let source: ConnectorID
        let audience: String
    }

    /// The audience an item was stamped with at normalize time (`for-you` / `group`),
    /// or `""` for sources that aren't split.
    static func audience(of item: BriefItem) -> String {
        let known: Set<String> = ["for-you", "group"]
        return item.urgencyHints.map(\.rawValue).first(where: known.contains) ?? ""
    }

    /// Maps a single DTO entry into a ``BriefEntry``, normalizing empty optionals to
    /// `nil` and parsing the url string. Shared by the lead and section entries.
    static func mapEntry(_ entry: SynthesizedBrief.Entry) -> BriefEntry {
        BriefEntry(
            headline: entry.headline,
            detail: entry.detail.flatMap { $0.isEmpty ? nil : $0 },
            url: entry.url.flatMap(URL.init(string:)),
            priority: entry.priority,
            ctaLabel: entry.ctaLabel.flatMap { $0.isEmpty ? nil : $0 },
            // Provenance the model cited; ids it invented simply don't parse and drop out.
            sourceItemIDs: entry.sourceItemIDs.compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        )
    }

    // MARK: - Strict JSON schema

    /// The strict JSON schema for ``SynthesizedBrief``.
    ///
    /// Built to OpenAI/OpenRouter strict-mode rules (design §8): every object sets
    /// `additionalProperties: false` and lists **every** property in `required`;
    /// optional fields are modeled as nullable unions (`["string","null"]`) rather
    /// than omitted from `required`. The validate-and-repair layer in `LLMKit` is
    /// the universal backstop for providers whose passthrough fidelity varies.
    public static let schema = JSONSchema(
        name: "daily_brief",
        schema: .object([
            "type": "object",
            "additionalProperties": false,
            "required": .array(["masthead", "lede", "summary", "mood", "sections"]),
            "properties": .object([
                "masthead": .object([
                    "type": "string",
                    "description": "Newspaper-style title named for the weekday, e.g. 'The Wednesday Brief'.",
                ]),
                "lede": .object([
                    "type": "string",
                    "description": "One short sentence — a kicker under the masthead.",
                ]),
                "summary": .object([
                    "type": "string",
                    "description": "The 'Daybrief' overview: 2-4 sentences summarizing the WHOLE day across ALL sources (mail, calendar, Slack, tasks). The headline card the reader sees first.",
                ]),
                "mood": .object([
                    "type": "string",
                    "enum": .array(BriefMood.allCases.map { .string($0.rawValue) }),
                    "description": """
                    The character of the day, chosen from the allowed values: \
                    'clear' (empty or light day), 'steady' (a normal, balanced day), \
                    'busy' (heavy, many competing demands), 'eventful' (defined by \
                    something big — a launch, a major meeting, a milestone).
                    """,
                ]),
                "sections": .object([
                    "type": "array",
                    "items": sectionSchema,
                ]),
            ]),
        ])
    )

    private static let sectionSchema: JSONValue = .object([
        "type": "object",
        "additionalProperties": false,
        "required": .array(["title", "source", "audience", "entries"]),
        "properties": .object([
            "title": .object([
                "type": "string",
                "description": "The source's display name, e.g. 'Gmail' — or 'Slack — For you' / 'Slack — Group' for the two Slack sections.",
            ]),
            "source": .object([
                "type": "string",
                "enum": .array(["gmail", "gcal", "slack", "notion"]),
                "description": "The connector this group is for. One section per source that has items; Slack gets two.",
            ]),
            "audience": .object([
                "type": "string",
                "enum": .array(["for-you", "group", ""]),
                "description": "For Slack, which half this section covers, matching the items' audience urgency hint. Empty for every other source.",
            ]),
            "entries": .object([
                "type": "array",
                "items": entrySchema,
            ]),
        ]),
    ])

    private static let entrySchema: JSONValue = .object([
        "type": "object",
        "additionalProperties": false,
        "required": .array(["headline", "detail", "url", "priority", "ctaLabel", "sourceItemIDs"]),
        "properties": entryProperties,
    ])

    /// The shared property set for an entry object, reused by both a section entry
    /// and the (nullable) lead story.
    private static let entryProperties: JSONValue = .object([
        "sourceItemIDs": .object([
            "type": "array",
            "items": .object(["type": "string"]),
            "description": "The `id` values of the ITEMS this entry was written from — at least one, copied exactly.",
        ]),
        "headline": .object(["type": "string"]),
        "detail": .object([
            "type": .array(["string", "null"]),
            "description": "A short paragraph of context, or null.",
        ]),
        "url": .object([
            "type": .array(["string", "null"]),
            "description": "A deep link back to the source item, or null.",
        ]),
        "priority": .object([
            "type": .array(["integer", "null"]),
            "description": "Lower = more important, or null when unranked.",
        ]),
        "ctaLabel": .object([
            "type": .array(["string", "null"]),
            "description": "A short call-to-action label, or null.",
        ]),
    ])
}

// MARK: - LLMError display

//
// `LLMError.displayReason` (a public, secret-free reason string) lives in `LLMKit`
// alongside the error; it spells out the actionable HTTP statuses (404 → choose a
// different model; 401 → re-enter the key). `synthesize(_:)` uses it directly when
// folding an `LLMError` into `PipelineError.synthesisFailed(reason:)`.
