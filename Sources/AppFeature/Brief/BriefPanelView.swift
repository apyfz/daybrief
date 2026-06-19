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
    /// The measured natural height of the current edition's content, used to size the
    /// panel to its content (capped at ``maxEditionHeight``).
    @State private var editionHeight: CGFloat = 0

    /// Dismisses the panel (close button). Injected because the panel is hosted in an
    /// AppKit-owned window, not a SwiftUI window we can close via `NSApp.keyWindow`.
    private let onClose: () -> Void
    /// Opens the setup / settings window. Injected because a detached `NSHostingView`
    /// can't reach the scene-connected `openWindow`; the app layer supplies one that can.
    private let onOpenSettings: () -> Void
    /// Reports the card's measured height up to the host controller so it can re-pin
    /// the panel whenever content changes (async hero image, refresh swap).
    private let onContentHeightChange: (CGFloat) -> Void

    public init(
        model: AppModel,
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onContentHeightChange = onContentHeightChange
    }

    /// Opens the setup / onboarding / settings window and brings the app forward
    /// (the window scene promotes the app to a regular, focusable app on appear).
    private func openSetup() {
        onOpenSettings()
        NSApp.activate()
    }

    /// Removes the item with `id` from the current edition (the lead or a section entry),
    /// once the user has dealt with it. Routed through the model so the change persists.
    private func dismiss(_ id: UUID) {
        Task { await model.dismissEntry(id: id) }
    }

    /// The fixed panel width — a single column, like a printed page.
    private let panelWidth: CGFloat = 380
    /// The tallest the edition can grow before it has to scroll. The panel sizes to its
    /// content and only scrolls when the content would exceed the screen — so most briefs
    /// show in full with no inner scrolling. `visibleFrame` already excludes the menu bar;
    /// the margin leaves room for the header bar + the popover's own chrome so it never
    /// runs flush to the screen edge.
    private var maxEditionHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return max(360, available - 120)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            // The editorial reading surface floats on a warm-paper sheet inside the
            // glass panel. The sheet keeps text legible on opaque paper while the
            // panel chrome / margins read as Liquid Glass (macOS 26). On the paper
            // fallback the sheet is visually quiet (paper-on-paper with a soft edge).
            content
                .paperSheet(cornerRadius: 14)
                // A slim dark-glass frame around the warm paper card.
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 10)
        }
        .frame(width: panelWidth)
        // The window's behind-window glass (BriefPanelController's dark NSGlassEffectView)
        // is the panel surface. We clip our own children to the same radius so the opaque
        // paper sheet doesn't square off the rounded glass corners; the header strip and
        // the margins around the paper sheet stay transparent and read as the dark glass.
        .clipShape(.rect(cornerRadius: 16))
        // Report the card's height up to the controller so it can re-pin the panel
        // whenever content changes (async hero image, refresh swap). This is the proven
        // signal that fires on those events.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, height in
                        onContentHeightChange(height)
                    }
            }
        }
        .tint(accent)
    }

    /// The edition's accent: the current brief's hero painting color (a per-edition
    /// palette), falling back to the app's golden accent when there is no brief, no
    /// hero, or no curated/parsable hex (design §brief-design-language, "per-edition
    /// accent").
    private var accent: Color {
        // Per-edition painting accents hurt legibility on busy art and dark glass
        // (e.g. a muddy olive on the Cézanne), so the brief uses the consistent golden
        // accent for the masthead and CTAs instead.
        DaybriefTheme.accent
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Leading close control — its own glass element on the leading margin.
            GlassToolbarCluster {
                Button {
                    onClose()
                } label: {
                    headerIcon("xmark", size: 11, weight: .semibold)
                }
                .modifier(GlassToolbarButton())
                .accessibilityLabel("Close")
            }

            // No title text here: the edition's masthead ("The Friday Brief") already
            // sits in the hero image below, so a header title would just duplicate it
            // (and a clear-glass header can't keep arbitrary text legible over any
            // backdrop). The header is the close control + the trailing actions only.
            Spacer(minLength: 0)

            // Trailing actions grouped in one glass cluster (refresh + settings).
            GlassToolbarCluster {
                if model.currentBrief != nil {
                    Button {
                        Task { await model.generateBriefNow() }
                    } label: {
                        headerIcon(
                            model.isGenerating ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                            size: 12,
                            weight: .medium
                        )
                        .symbolEffect(.rotate, isActive: model.isGenerating)
                    }
                    .modifier(GlassToolbarButton())
                    .disabled(model.isGenerating)
                    .accessibilityLabel("Refresh today's brief")
                }

                Button {
                    openSetup()
                } label: {
                    headerIcon("gearshape", size: 12, weight: .medium)
                }
                .modifier(GlassToolbarButton())
                .accessibilityLabel("Settings")
            }
        }
        // Align the header controls with the slim glass frame (matching the paper card's
        // side margins), with a little glass above them so the frame wraps the top too.
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// A toolbar icon label sized consistently for the header glass buttons.
    private func headerIcon(_ name: String, size: CGFloat, weight: Font.Weight) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            // White glyph on a dark-gray button so the controls read clearly on the dark
            // glass header, regardless of the wallpaper behind it.
            .foregroundStyle(.white)
            .frame(width: 32, height: 28)
            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        // Consistent golden accent for legibility (see `accent`); per-edition painting
        // colors were too low-contrast for the masthead/CTAs.
        let editionAccent = DaybriefTheme.accent

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
                    .font(DaybriefTheme.serifItalic(16))
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
                    accent: editionAccent,
                    onDismiss: dismiss
                )
            }

            // On a quiet day (no lead, no entries) nothing is rendered here — the lede
            // under the hero already carries it; no separate "quiet day" card.
            if !vm.sections.allSatisfy({ $0.entries.isEmpty }) {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(vm.sections.filter { !$0.entries.isEmpty }) { section in
                        BriefSectionView(
                            section: section,
                            ctaLabels: ctaLabels,
                            accent: editionAccent,
                            onDismiss: dismiss
                        )
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

        // Size the panel to the edition's measured content height so it shows in full,
        // only scrolling when the content would be taller than the screen. A plain
        // ScrollView/ViewThatFits collapses to zero inside a self-sizing menu-bar popover
        // (it gets no height proposal), so we measure the content and set the height
        // explicitly. The initial placeholder is modest to avoid a tall first-frame flash
        // before the measured height lands.
        return ScrollView {
            editionBody
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    editionHeight = height
                }
        }
        .frame(height: editionHeight == 0 ? min(maxEditionHeight, 500) : min(editionHeight, maxEditionHeight))
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

// MARK: - Header glass chrome (macOS 26)

/// Groups the header toolbar buttons in a single ``GlassEffectContainer`` on
/// macOS 26 so they render as one cohesive glass cluster (and blend when adjacent);
/// a plain `HStack` on earlier systems.
private struct GlassToolbarCluster<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) { content }
            }
        } else {
            HStack(spacing: 6) { content }
        }
    }
}

/// Renders a header toolbar button as interactive Liquid Glass on macOS 26
/// (`.buttonStyle(.glass)`), falling back to the flat `.plain` style on earlier
/// systems. Keeps the button's action, label, and accessibility intact.
private struct GlassToolbarButton: ViewModifier {
    func body(content: Content) -> some View {
        // The button draws its own dark-gray capsule (see `headerIcon`), so use the plain
        // style rather than the system glass capsule.
        content.buttonStyle(.plain)
    }
}
