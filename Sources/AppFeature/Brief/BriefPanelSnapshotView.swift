import BriefRender
import DaybriefCore
import SwiftUI

/// A non-scrolling, snapshot-friendly rendering of a brief edition for offscreen
/// rasterization (`ImageRenderer`) and SwiftUI previews.
///
/// `ImageRenderer` does not draw the content of a `ScrollView` during its offscreen
/// pass, and it does not rasterize the macOS 26 Liquid Glass material — so the live
/// ``BriefPanelView`` (which uses both) snapshots as a blank page. This view composes
/// the *same* editorial subviews (``BriefHeroHeaderView``, ``BriefLeadView``,
/// ``BriefSectionView``, ``BriefConnectorNoticesView``, ``BriefColophonView``, the same
/// masthead/lede/credit chrome, colored by the same per-edition accent) inside a plain
/// `VStack` over solid paper, so the full edition renders. It is a faithful stand-in
/// for the panel's body, used only by the snapshot tool — the shipping panel is
/// unchanged.
@MainActor
public struct BriefPanelSnapshotView: View {
    private let brief: Brief

    /// Creates a snapshot view for `brief`.
    public init(brief: Brief) {
        self.brief = brief
    }

    /// The fixed panel width, matching ``BriefPanelView``'s single-column page.
    private let panelWidth: CGFloat = 380

    public var body: some View {
        let vm = BriefRenderer().viewModel(brief)
        let ctaLabels = ctaLabelMap(brief)
        let editionAccent = vm.accentHex.flatMap(Color.init(hex:)) ?? DaybriefTheme.accent

        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 22) {
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

                if let lead = vm.lead {
                    BriefLeadView(
                        lead: lead,
                        ctaLabel: vm.leadCTALabel ?? "Let's do it",
                        accent: editionAccent,
                        // The offscreen `ImageRenderer` pass can't rasterize Liquid
                        // Glass, so use the starburst CTA in snapshots.
                        usesGlassCTA: false
                    )
                }

                VStack(alignment: .leading, spacing: 26) {
                    ForEach(vm.sections.filter { !$0.entries.isEmpty }) { section in
                        BriefSectionView(
                            section: section,
                            ctaLabels: ctaLabels,
                            accent: editionAccent,
                            usesGlassCTA: false
                        )
                        .padding(16)
                        .editorialCard()
                    }
                }

                if !vm.connectorErrors.isEmpty {
                    BriefConnectorNoticesView(errors: vm.connectorErrors)
                        .padding(.top, 4)
                }

                BriefColophonView(colophon: vm.colophon)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        .frame(width: panelWidth)
        .background(DaybriefTheme.paper)
        .tint(editionAccent)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .frame(width: 22, height: 22)

            Text(headerTitle)
                .font(DaybriefTheme.serifBody(13))
                .foregroundStyle(DaybriefTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var headerTitle: String {
        let title = brief.masthead.isEmpty ? mastheadForToday(brief.generatedAt) : brief.masthead
        return "\(title) · \(Self.headerDate.string(from: brief.generatedAt))"
    }

    private func ctaLabelMap(_ brief: Brief) -> [UUID: String] {
        var map: [UUID: String] = [:]
        for section in brief.sections {
            for entry in section.entries where entry.ctaLabel?.isEmpty == false {
                map[entry.id] = entry.ctaLabel
            }
        }
        return map
    }

    private func mastheadForToday(_ date: Date) -> String {
        "The \(Self.weekday.string(from: date)) Brief"
    }

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
