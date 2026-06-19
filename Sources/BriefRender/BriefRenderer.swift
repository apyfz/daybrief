import DaybriefCore
import Foundation

/// Turns a synthesized ``Brief`` into the shapes the rest of the app consumes:
/// a self-contained HTML archive, a Markdown export, and a presentation-ready
/// ``BriefViewModel`` for the SwiftUI layer.
///
/// Pure and deterministic: no SwiftUI/AppKit, no I/O, no wall-clock reads. The
/// "now" used for relative-time hints is taken from an injected ``DateProvider``,
/// and time formatting from an injected `Calendar`, so every output is fully
/// reproducible (and snapshot-testable). All user-supplied text is HTML-escaped
/// and links are scheme-checked, so a crafted title/body cannot inject markup.
public struct BriefRenderer: Sendable {
    /// The clock used for relative-time hints (e.g. "2 hours ago").
    public let dateProvider: any DateProvider
    /// The calendar / locale / time zone used to format absolute timestamps.
    public let calendar: Calendar

    /// Creates a renderer.
    ///
    /// - Parameters:
    ///   - dateProvider: the source of "now" for relative-time hints
    ///     (defaults to the system clock).
    ///   - calendar: the calendar used to format absolute times
    ///     (defaults to `Calendar.current`).
    public init(
        dateProvider: any DateProvider = SystemDateProvider(),
        calendar: Calendar = .current
    ) {
        self.dateProvider = dateProvider
        self.calendar = calendar
    }

    // MARK: - View model

    /// Projects `brief` into a presentation-ready ``BriefViewModel`` for the view layer.
    ///
    /// Entries are pre-sorted by priority (then stable original order), detail/links
    /// are cleaned and scheme-checked, and the generation time is pre-formatted into
    /// both relative and absolute strings. The view layer renders this with no logic.
    public func viewModel(_ brief: Brief) -> BriefViewModel {
        let now = dateProvider.now()

        // With no signals read, there's nothing real to brief — any lead/sections the model
        // produced are filler (e.g. a "clear day ahead" headline dressed up as a Lead). Drop
        // them so the panel shows the genuine quiet-day state instead of a fabricated lead.
        let hasSignals = brief.signalsRead > 0

        // A Lead is "the single most important thing to act on". On a model-declared
        // "clear" (quiet/light) day, a lead with no link and no call-to-action is a
        // quiet-day statement ("Nothing pressing today") the model dressed up as a Lead —
        // that belongs in the lede, not the Lead slot. Drop it (the lede carries the day);
        // an actionable lead, or any lead on a busier day, is kept.
        let leadIsClearDayFiller = brief.mood == .clear
            && brief.lead.map { $0.url == nil && BriefPresentation.cleaned($0.ctaLabel) == nil } == true
        let effectiveLead = (hasSignals && !leadIsClearDayFiller) ? brief.lead : nil
        let effectiveSections = hasSignals ? brief.sections : []

        let lead = effectiveLead.map(entryViewModel)

        let sections = effectiveSections.map { section in
            BriefViewModel.Section(
                id: section.id,
                title: section.title,
                entries: BriefPresentation.orderedEntries(section.entries).map(entryViewModel)
            )
        }

        let errors = brief.connectorErrors.map { summary in
            BriefViewModel.ConnectorError(
                connectorId: summary.connectorId,
                connectorDisplay: BriefPresentation.connectorDisplayName(summary.connectorId),
                kind: summary.kind,
                message: summary.message
            )
        }

        // Surfaced = the lead (if any) + every section entry. Computed here, factually,
        // never read from the model — it must always match what the edition actually shows
        // (so it reflects the signal-gated lead/sections, not the raw model output).
        let surfaced = (effectiveLead == nil ? 0 : 1)
            + effectiveSections.reduce(0) { $0 + $1.entries.count }

        return BriefViewModel(
            id: brief.id,
            generatedAtRelative: "Generated \(BriefPresentation.relativeTime(of: brief.generatedAt, now: now))",
            generatedAtAbsolute: BriefPresentation.absoluteTime(brief.generatedAt, calendar: calendar),
            spaceFilterDisplay: BriefPresentation.spaceDisplay(brief.spaceFilter),
            lead: lead,
            leadCTALabel: effectiveLead.flatMap { BriefPresentation.cleaned($0.ctaLabel) },
            sections: sections,
            connectorErrors: errors,
            colophon: BriefPresentation.colophon(
                generatedAt: brief.generatedAt,
                signalsRead: brief.signalsRead,
                surfaced: surfaced,
                sources: brief.sources,
                calendar: calendar
            ),
            accentHex: brief.hero?.accentHex
        )
    }

    private func entryViewModel(_ entry: BriefEntry) -> BriefViewModel.Entry {
        let link = BriefPresentation.safeLink(entry.url)
        return BriefViewModel.Entry(
            id: entry.id,
            headline: entry.headline,
            detail: BriefPresentation.cleaned(entry.detail),
            link: link,
            linkLabel: link.map(BriefPresentation.linkLabel),
            priority: entry.priority
        )
    }

    // MARK: - HTML

    /// Renders `brief` as a clean, self-contained HTML document (its own inline CSS,
    /// no external assets) suitable for an on-disk archive copy of the brief.
    ///
    /// All interpolated user content is HTML-escaped and only `http`/`https` links
    /// are emitted as anchors, so the archive is injection-safe to open in any browser.
    public func renderHTML(_ brief: Brief) -> String {
        let vm = viewModel(brief)
        let esc = HTMLEscaping.escape

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(documentTitle(vm)))</title>
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { font: 16px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
               margin: 0; padding: 2rem 1rem; background: Canvas; color: CanvasText; }
        main { max-width: 44rem; margin: 0 auto; }
        header { margin-bottom: 2rem; }
        h1 { font-size: 1.5rem; margin: 0 0 0.25rem; }
        .meta { color: GrayText; font-size: 0.85rem; margin: 0; }
        .lead { margin: 0 0 2rem; padding-bottom: 1.5rem;
                border-bottom: 2px solid color-mix(in srgb, GrayText 30%, transparent); }
        .lead .kicker { font-variant: small-caps; letter-spacing: 0.08em; font-size: 0.75rem;
                        color: GrayText; margin: 0 0 0.4rem; }
        .lead h2 { font-size: 1.6rem; line-height: 1.2; margin: 0; font-weight: 700; }
        .lead .detail { color: GrayText; margin: 0.5rem 0 0; }
        .lead a { display: inline-block; margin-top: 0.5rem; font-size: 0.9rem; }
        section { margin-bottom: 1.75rem; }
        section > h2 { font-size: 1.1rem; margin: 0 0 0.5rem; padding-bottom: 0.25rem;
                       border-bottom: 1px solid color-mix(in srgb, GrayText 35%, transparent); }
        ul.entries { list-style: none; margin: 0; padding: 0; }
        li.entry { padding: 0.5rem 0; }
        li.entry + li.entry { border-top: 1px solid color-mix(in srgb, GrayText 18%, transparent); }
        .headline { font-weight: 600; }
        .detail { color: GrayText; margin: 0.15rem 0 0; }
        li.entry a { display: inline-block; margin-top: 0.2rem; font-size: 0.85rem; }
        .errors { margin-top: 2rem; padding: 0.75rem 1rem;
                  border: 1px solid color-mix(in srgb, #b00 50%, transparent); border-radius: 0.5rem; }
        .errors h2 { font-size: 0.95rem; margin: 0 0 0.4rem; }
        .errors ul { margin: 0; padding-left: 1.1rem; }
        .errors .kind { font-variant: small-caps; color: GrayText; }
        .empty { color: GrayText; font-style: italic; }
        .colophon { margin-top: 2.5rem; padding-top: 1rem;
                    border-top: 1px solid color-mix(in srgb, GrayText 25%, transparent);
                    font-variant: small-caps; letter-spacing: 0.06em;
                    font-size: 0.78rem; color: GrayText; }
        </style>
        </head>
        <body>
        <main>
        <header>
        <h1>\(esc(documentTitle(vm)))</h1>
        <p class="meta">\(esc(vm.generatedAtAbsolute)) · \(esc(vm.generatedAtRelative))</p>
        </header>

        """

        // Lead story: the single most important item, set large above the sections.
        if let lead = vm.lead {
            html += "<div class=\"lead\">\n<p class=\"kicker\">Lead</p>\n"
            html += "<h2>\(esc(lead.headline))</h2>\n"
            if let detail = lead.detail {
                html += "<p class=\"detail\">\(esc(detail))</p>\n"
            }
            if let link = lead.link, let label = vm.leadCTALabel ?? lead.linkLabel {
                html += "<a href=\"\(esc(link.absoluteString))\""
                    + " rel=\"noopener noreferrer\">\(esc(label))</a>\n"
            }
            html += "</div>\n"
        }

        if vm.isEmpty {
            html += "<p class=\"empty\">No items in this brief.</p>\n"
        } else {
            for section in vm.sections where !section.entries.isEmpty {
                html += "<section>\n<h2>\(esc(section.title))</h2>\n<ul class=\"entries\">\n"
                for entry in section.entries {
                    html += "<li class=\"entry\">\n"
                    html += "<div class=\"headline\">\(esc(entry.headline))</div>\n"
                    if let detail = entry.detail {
                        html += "<p class=\"detail\">\(esc(detail))</p>\n"
                    }
                    if let link = entry.link, let label = entry.linkLabel {
                        // href value is escaped in a double-quoted attribute context.
                        // Styled via the `li.entry a` descendant selector — no class needed.
                        html += "<a href=\"\(esc(link.absoluteString))\""
                            + " rel=\"noopener noreferrer\">\(esc(label))</a>\n"
                    }
                    html += "</li>\n"
                }
                html += "</ul>\n</section>\n"
            }
        }

        if !vm.connectorErrors.isEmpty {
            html += "<div class=\"errors\">\n<h2>Some sources could not be reached</h2>\n<ul>\n"
            for error in vm.connectorErrors {
                html += "<li><strong>\(esc(error.connectorDisplay))</strong>"
                    + " <span class=\"kind\">\(esc(error.kind.rawValue))</span> — \(esc(error.message))</li>\n"
            }
            html += "</ul>\n</div>\n"
        }

        // Colophon: a quiet, print-style provenance footer at the foot of the edition.
        if !vm.colophon.isEmpty {
            html += "<p class=\"colophon\">\(esc(vm.colophon))</p>\n"
        }

        html += """
        </main>
        </body>
        </html>
        """
        return html
    }

    // MARK: - Markdown

    /// Renders `brief` as a Markdown document.
    ///
    /// Headlines, details, and link labels are emitted verbatim (Markdown is plain
    /// text); only scheme-checked `http`/`https` links become `[label](url)`.
    public func renderMarkdown(_ brief: Brief) -> String {
        let vm = viewModel(brief)
        var lines: [String] = []

        var heading = "# Daybrief"
        if let space = vm.spaceFilterDisplay {
            heading += " — \(space)"
        }
        lines.append(heading)
        lines.append("")
        lines.append("_\(vm.generatedAtAbsolute) · \(vm.generatedAtRelative)_")

        // Lead story: set off as a second-level heading above the sections so the
        // edition leads with its single most important item.
        if let lead = vm.lead {
            lines.append("")
            lines.append("## \(lead.headline)")
            if let detail = lead.detail {
                lines.append("")
                lines.append(detail)
            }
            if let link = lead.link, let label = vm.leadCTALabel ?? lead.linkLabel {
                lines.append("")
                lines.append("[\(label)](\(link.absoluteString))")
            }
        }

        if vm.isEmpty {
            lines.append("")
            lines.append("_No items in this brief._")
        } else {
            for section in vm.sections where !section.entries.isEmpty {
                lines.append("")
                lines.append("## \(section.title)")
                lines.append("")
                for entry in section.entries {
                    lines.append("- \(entry.headline)")
                    if let detail = entry.detail {
                        lines.append("  \(detail)")
                    }
                    if let link = entry.link, let label = entry.linkLabel {
                        lines.append("  [\(label)](\(link.absoluteString))")
                    }
                }
            }
        }

        if !vm.connectorErrors.isEmpty {
            lines.append("")
            lines.append("## Some sources could not be reached")
            lines.append("")
            for error in vm.connectorErrors {
                lines.append("- **\(error.connectorDisplay)** (\(error.kind.rawValue)) — \(error.message)")
            }
        }

        // Colophon: a quiet provenance footer, italicized like the meta line.
        if !vm.colophon.isEmpty {
            lines.append("")
            lines.append("---")
            lines.append("")
            lines.append("_\(vm.colophon)_")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private func documentTitle(_ vm: BriefViewModel) -> String {
        if let space = vm.spaceFilterDisplay {
            return "Daybrief — \(space)"
        }
        return "Daybrief"
    }
}
