import AppKit
import BriefRender
import DaybriefCore
import SwiftUI

/// The showpiece: the daily brief presented as a calm, literary morning
/// periodical — masthead over a fine-art hero, vertical date/time rails, an
/// italic serif lede, and titled "movements" of prioritized action cards, each
/// with a golden starburst CTA. Lives in the `MenuBarExtra(.window)` panel.
///
/// This view owns *presentation only*. Ordering, link-safety, and time formatting
/// come from ``BriefRenderer/viewModel(_:)``; the editorial chrome (masthead, lede,
/// hero, generation time) is read from the originating ``Brief`` on the model.
@MainActor
public struct BriefPanelView: View {
    @State private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    /// The fixed panel width — a single column, like a printed page.
    private let panelWidth: CGFloat = 380

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.4)
            content
        }
        .frame(width: panelWidth)
        .frame(maxHeight: 620)
        .background(panelSurface)
        .tint(DaybriefTheme.accent)
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

    @ViewBuilder
    private func edition(for brief: Brief) -> some View {
        let vm = BriefRenderer().viewModel(brief)
        let ctaLabels = ctaLabelMap(brief)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BriefHeroHeaderView(
                    hero: brief.hero,
                    masthead: brief.masthead.isEmpty ? mastheadForToday(brief.generatedAt) : brief.masthead,
                    dateline: Self.dateline.string(from: brief.generatedAt).uppercased(),
                    generationTime: Self.railTime.string(from: brief.generatedAt)
                )

                if !brief.lede.isEmpty {
                    Text(brief.lede)
                        .font(DaybriefTheme.serifDisplay(16).italic())
                        .foregroundStyle(DaybriefTheme.ink.opacity(0.85))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if vm.isEmpty {
                    quietDay
                } else {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(vm.sections.filter { !$0.entries.isEmpty }) { section in
                            BriefSectionView(section: section, ctaLabels: ctaLabels)
                                .modifier(EditorialCardModifier())
                        }
                    }
                }

                if !vm.connectorErrors.isEmpty {
                    BriefConnectorNoticesView(errors: vm.connectorErrors)
                        .padding(.top, 4)
                }

                Text(vm.generatedAtRelative)
                    .font(DaybriefTheme.serifBody(10))
                    .foregroundStyle(DaybriefTheme.inkSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
    }

    /// The intentional, calm "quiet day" state: a brief exists but holds no
    /// action items. Emptiness is a feature — we let the lede carry it and add a
    /// single reassuring line rather than padding the page.
    private var quietDay: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DaybriefTheme.accent.opacity(0.8))
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
