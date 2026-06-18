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
            sources: resolvedSources
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
        sources: [ConnectorID]
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

        let lead = synthesized.lead.map(Self.mapEntry)
        let sections = synthesized.sections.map { section in
            BriefSection(title: section.title, entries: section.entries.map(Self.mapEntry))
        }

        return Brief(
            generatedAt: generatedAt,
            spaceFilter: spaceFilter,
            masthead: masthead,
            lede: synthesized.lede,
            lead: lead,
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

    /// Maps a single DTO entry into a ``BriefEntry``, normalizing empty optionals to
    /// `nil` and parsing the url string. Shared by the lead and section entries.
    static func mapEntry(_ entry: SynthesizedBrief.Entry) -> BriefEntry {
        BriefEntry(
            headline: entry.headline,
            detail: entry.detail.flatMap { $0.isEmpty ? nil : $0 },
            url: entry.url.flatMap(URL.init(string:)),
            priority: entry.priority,
            ctaLabel: entry.ctaLabel.flatMap { $0.isEmpty ? nil : $0 }
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
            "required": .array(["masthead", "lede", "mood", "lead", "sections"]),
            "properties": .object([
                "masthead": .object([
                    "type": "string",
                    "description": "Newspaper-style title named for the weekday, e.g. 'The Wednesday Brief'.",
                ]),
                "lede": .object([
                    "type": "string",
                    "description": "One or two sentences of editorial prose summarizing the day.",
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
                "lead": leadSchema,
                "sections": .object([
                    "type": "array",
                    "items": sectionSchema,
                ]),
            ]),
        ])
    )

    /// The lead-story schema: a nullable entry object (the single most important item
    /// of the day, not repeated in `sections`), or `null` on a quiet day.
    private static let leadSchema: JSONValue = .object([
        "type": .array(["object", "null"]),
        "additionalProperties": false,
        "required": .array(["headline", "detail", "url", "priority", "ctaLabel"]),
        "description": "The single most important item of the day, or null when nothing leads.",
        "properties": entryProperties,
    ])

    private static let sectionSchema: JSONValue = .object([
        "type": "object",
        "additionalProperties": false,
        "required": .array(["title", "entries"]),
        "properties": .object([
            "title": .object(["type": "string"]),
            "entries": .object([
                "type": "array",
                "items": entrySchema,
            ]),
        ]),
    ])

    private static let entrySchema: JSONValue = .object([
        "type": "object",
        "additionalProperties": false,
        "required": .array(["headline", "detail", "url", "priority", "ctaLabel"]),
        "properties": entryProperties,
    ])

    /// The shared property set for an entry object, reused by both a section entry
    /// and the (nullable) lead story.
    private static let entryProperties: JSONValue = .object([
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
