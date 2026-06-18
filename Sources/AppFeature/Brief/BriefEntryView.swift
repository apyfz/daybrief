import BriefRender
import DaybriefCore
import SwiftUI

/// A single editorial item: a serif headline, a paragraph of context written as
/// if the assistant has read the source threads, and a playful golden starburst
/// CTA badge ("Let's do it →") that opens the originating link.
///
/// The badge is only shown when the entry has a link-safe URL to open; entries
/// without a destination still render their headline + context cleanly.
struct BriefEntryView: View {
    /// The presentation-ready entry from ``BriefRenderer``.
    let entry: BriefViewModel.Entry
    /// The CTA label to print on the badge (e.g. "Let's do it"); defaults sensibly.
    let ctaLabel: String
    /// The edition's accent, sampled from its hero painting; defaults to the golden accent.
    var accent: Color = DaybriefTheme.accent
    /// Whether the CTA badge may use the macOS 26 Liquid Glass rendering. The offscreen
    /// snapshot tool sets this `false` (`ImageRenderer` can't rasterize Liquid Glass).
    var usesGlassCTA: Bool = true

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.headline)
                .font(DaybriefTheme.serifDisplay(18))
                .foregroundStyle(DaybriefTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = entry.detail {
                Text(detail)
                    .font(DaybriefTheme.serifBody(13))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let link = entry.link {
                Button {
                    openURL(link)
                } label: {
                    ActionBadge(label: ctaLabel, accent: accent, forcesFallback: !usesGlassCTA)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ctaLabel): \(entry.headline)")
                .accessibilityHint(entry.linkLabel.map { "Opens \($0)" } ?? "Opens the source")
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
