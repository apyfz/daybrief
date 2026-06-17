import AppKit
import BriefRender
import DaybriefCore
import SwiftUI

/// The showpiece: the daily brief presented as a calm, literary morning
/// periodical — masthead over a fine-art hero, vertical date/time rails, an italic
/// serif lede, a large **lead story**, and titled "movements" of prioritized action
/// cards, each with a starburst CTA, closed by a print-style **colophon**. Lives in
/// the `MenuBarExtra(.window)` panel.
///
/// This view owns *presentation only*. Ordering, link-safety, time formatting, the
/// lead projection, the factual colophon, and the per-edition accent hex all come
/// from ``BriefRenderer/viewModel(_:)``; the editorial chrome (masthead, lede, hero)
/// is read from the originating ``Brief`` on the model. Each edition is colored by
/// its hero painting's accent (``accent``), falling back to the app's golden accent.
@MainActor
public struct BriefPanelView: View {
    @State private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    /// The measured natural height of the current edition's content, used to size the
    /// panel to its content (capped at ``maxEditionHeight``).
    @State private var editionHeight: CGFloat = 0

    public init(model: AppModel) {
        self.model = model
    }

    /// Opens the setup / onboarding / settings window and brings the app forward
    /// (the window scene promotes the app to a regular, focusable app on appear).
    private func openSetup() {
        openWindow(id: DaybriefWindow.mainID)
        NSApp.activate()
    }

    /// The fixed panel width — a single column, like a printed page.
    private let panelWidth: CGFloat = 380
    /// Cap the edition's height so a long brief scrolls instead of overflowing the
    /// screen; shorter editions (e.g. a quiet day) let the panel shrink to fit.
    private static let maxEditionHeight: CGFloat = 600

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.4)
            content
        }
        .frame(width: panelWidth)
        .background(panelSurface)
        .tint(accent)
    }

    /// The edition's accent: the current brief's hero painting color (a per-edition
    /// palette), falling back to the app's golden accent when there is no brief, no
    /// hero, or no curated/parsable hex (design §brief-design-language, "per-edition
    /// accent").
    private var accent: Color {
        model.currentBrief?.hero?.accentHex.flatMap(Color.init(hex:)) ?? DaybriefTheme.accent
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text(headerTitle)
                .font(DaybriefTheme.serifBody(13))
                .foregroundStyle(DaybriefTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if model.currentBrief != nil {
                Button {
                    Task { await model.generateBriefNow() }
                } label: {
                    Image(systemName: model.isGenerating ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .symbolEffect(.rotate, isActive: model.isGenerating)
                }
                .buttonStyle(.plain)
                .disabled(model.isGenerating)
                .accessibilityLabel("Refresh today's brief")
            }

            Button {
                openSetup()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// The thin title strip, e.g. "The Wednesday Brief · June 17".
    private var headerTitle: String {
        guard let brief = model.currentBrief else { return "Daybrief" }
        let title = brief.masthead.isEmpty ? mastheadForToday(brief.generatedAt) : brief.masthead
        return "\(title) · \(Self.headerDate.string(from: brief.generatedAt))"
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        if let brief = model.currentBrief {
            edition(for: brief)
        } else if model.isGenerating {
            BriefLoadingStateView()
        } else if model.setup != .ready {
            // Fresh / incomplete setup with no brief yet → invite onboarding rather
            // than showing a brief error (you can't synthesize without a model).
            BriefWelcomeStateView(onGetStarted: { openSetup() })
        } else if let error = model.lastError {
            BriefErrorStateView(
                message: error,
                isGenerating: model.isGenerating,
                onRetry: { Task { await model.generateBriefNow() } }
            )
        } else {
            BriefEmptyStateView(
                isGenerating: model.isGenerating,
                onGenerate: { Task { await model.generateBriefNow() } }
            )
        }
    }

    // MARK: - The edition

    private func edition(for brief: Brief) -> some View {
        let vm = BriefRenderer().viewModel(brief)
        let ctaLabels = ctaLabelMap(brief)
        // Color this edition by its own painting (passed through ``BriefViewModel``),
        // independent of which brief is "current".
        let editionAccent = vm.accentHex.flatMap(Color.init(hex:)) ?? DaybriefTheme.accent

        let editionBody = VStack(alignment: .leading, spacing: 22) {
            BriefHeroHeaderView(
                hero: brief.hero,
                masthead: brief.masthead.isEmpty ? mastheadForToday(brief.generatedAt) : brief.masthead,
                dateline: Self.dateline.string(from: brief.generatedAt).uppercased(),
                generationTime: Self.railTime.string(from: brief.generatedAt),
                accent: editionAccent
            )

            if !brief.lede.isEmpty {
                Text(brief.lede)
                    .font(DaybriefTheme.serifDisplay(16).italic())
                    .foregroundStyle(DaybriefTheme.ink.opacity(0.85))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The lead story, set large directly under the lede and apart from the
            // sections below. The engine keeps it out of `sections`, so it is not
            // duplicated.
            if let lead = vm.lead {
                BriefLeadView(
                    lead: lead,
                    ctaLabel: vm.leadCTALabel ?? "Let's do it",
                    accent: editionAccent
                )
            }

            if vm.isEmpty {
                quietDay(accent: editionAccent)
            } else if !vm.sections.allSatisfy({ $0.entries.isEmpty }) {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(vm.sections.filter { !$0.entries.isEmpty }) { section in
                        BriefSectionView(section: section, ctaLabels: ctaLabels, accent: editionAccent)
                            .modifier(EditorialCardModifier())
                    }
                }
            }

            if !vm.connectorErrors.isEmpty {
                BriefConnectorNoticesView(errors: vm.connectorErrors)
                    .padding(.top, 4)
            }

            // The colophon replaces the old relative-time footer: a quiet,
            // print-style provenance line at the foot of the edition.
            BriefColophonView(colophon: vm.colophon)
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 22)

        // Size the panel to the edition's measured content height, capped so a long
        // brief scrolls within the cap. A plain ScrollView/ViewThatFits collapses to
        // zero inside a self-sizing menu-bar popover (it gets no height proposal), so
        // we measure the content and set the height explicitly.
        return ScrollView {
            editionBody
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    editionHeight = height
                }
        }
        .frame(height: editionHeight == 0 ? Self.maxEditionHeight : min(editionHeight, Self.maxEditionHeight))
    }

    /// The intentional, calm "quiet day" state: a brief exists but holds no
    /// action items. Emptiness is a feature — we let the lede carry it and add a
    /// single reassuring line rather than padding the page.
    private func quietDay(accent: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(accent.opacity(0.8))
                .accessibilityHidden(true)
            Text("Nothing demanding your attention. Enjoy the quiet.")
                .font(DaybriefTheme.serifBody(13).italic())
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .modifier(EditorialCardModifier())
    }

    // MARK: - Panel surface (Liquid Glass on macOS 26)

    @ViewBuilder
    private var panelSurface: some View {
        if #available(macOS 26.0, *) {
            DaybriefTheme.paper
                .glassEffect(.regular, in: .rect(cornerRadius: 0))
        } else {
            DaybriefTheme.paper
        }
    }

    // MARK: - Derived editorial strings

    /// Maps each entry id to its LLM-chosen CTA label, since the projected view
    /// model intentionally drops `ctaLabel`. Falls back are handled downstream.
    private func ctaLabelMap(_ brief: Brief) -> [UUID: String] {
        var map: [UUID: String] = [:]
        for section in brief.sections {
            for entry in section.entries {
                if let label = entry.ctaLabel, !label.isEmpty {
                    map[entry.id] = label
                }
            }
        }
        return map
    }

    /// A weekday-derived masthead fallback ("The Wednesday Brief") for legacy
    /// briefs that predate the editorial fields.
    private func mastheadForToday(_ date: Date) -> String {
        "The \(Self.weekday.string(from: date)) Brief"
    }

    // MARK: - Formatters (locale-aware; configured once, only ever read)

    //
    // `DateFormatter` is `Sendable` on this SDK, so these shared instances need no
    // extra isolation annotation. They are built once and never mutated, so
    // concurrent reads are safe.

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMd")
        return f
    }()

    /// e.g. "17 jun 2026" → uppercased at the call site to "17 JUN 2026".
    private static let dateline: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    private static let railTime: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("hh:mm a")
        return f
    }()
}

/// Wraps a section in the shared editorial card chrome. Kept as a modifier so the
/// `editorialCard()` extension from the design system can evolve independently.
private struct EditorialCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .editorialCard()
    }
}
