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
    public static let defaultSynthesisTimeout: Duration = .seconds(60)

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
        connectorErrors: [ConnectorErrorSummary] = []
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
        } catch {
            throw PipelineError.synthesisFailed(reason: "\(type(of: error))")
        }

        return mapToBrief(
            synthesized,
            generatedAt: now,
            weekday: weekday,
            spaceFilter: spaceFilter,
            connectorErrors: connectorErrors
        )
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
        connectorErrors: [ConnectorErrorSummary]
    ) -> Brief {
        // Trust the model's masthead when it followed the "The <Weekday> Brief"
        // instruction; otherwise fall back to the deterministic, correct form.
        let masthead = synthesized.masthead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "The \(weekday) Brief"
            : synthesized.masthead

        let sections = synthesized.sections.map { section in
            BriefSection(
                title: section.title,
                entries: section.entries.map { entry in
                    BriefEntry(
                        headline: entry.headline,
                        detail: entry.detail.flatMap { $0.isEmpty ? nil : $0 },
                        url: entry.url.flatMap(URL.init(string:)),
                        priority: entry.priority,
                        ctaLabel: entry.ctaLabel.flatMap { $0.isEmpty ? nil : $0 }
                    )
                }
            )
        }

        return Brief(
            generatedAt: generatedAt,
            spaceFilter: spaceFilter,
            masthead: masthead,
            lede: synthesized.lede,
            hero: HeroArtworkCatalog.heroForDate(generatedAt, calendar: calendar),
            sections: sections,
            connectorErrors: connectorErrors
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
            "required": .array(["masthead", "lede", "sections"]),
            "properties": .object([
                "masthead": .object([
                    "type": "string",
                    "description": "Newspaper-style title named for the weekday, e.g. 'The Wednesday Brief'.",
                ]),
                "lede": .object([
                    "type": "string",
                    "description": "One or two sentences of editorial prose summarizing the day.",
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
        "properties": .object([
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
        ]),
    ])
}

// MARK: - LLMError display

private extension LLMError {
    /// A short, secret-free reason string for ``PipelineError/synthesisFailed(reason:)``.
    ///
    /// Deliberately avoids echoing `httpStatus.body` (provider error payloads may
    /// carry sensitive detail) and never includes the request body.
    var displayReason: String {
        switch self {
        case let .missingAPIKey(provider):
            return "no API key for \(provider)"
        case let .invalidBaseURL(provider):
            return "invalid base URL for \(provider)"
        case .requestEncodingFailed:
            return "the request could not be encoded"
        case let .httpStatus(code, _):
            return "the model service returned HTTP \(code)"
        case let .malformedResponse(detail):
            return detail
        case let .streamDecodingFailed(detail):
            return "the model stream could not be read (\(detail))"
        case let .structuredOutputUnrepairable(detail):
            return "the model's output could not be parsed (\(detail))"
        case let .refused(detail):
            return "the model refused to answer (\(detail))"
        case .cancelled:
            return "the request was cancelled"
        }
    }
}
