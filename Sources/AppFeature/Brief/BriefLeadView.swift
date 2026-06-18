import BriefRender
import DaybriefCore
import SwiftUI

/// The lead story: the single most important item of the day, set large directly
/// under the lede and visually set apart from the sections below it — a real
/// headline, not just the first row of a list (design §brief-design-language,
/// "lead story").
///
/// It reads as the front-page item: a small letterspaced "Lead" kicker in the
/// edition's accent, a heavier serif headline a step larger than a section entry,
/// the context paragraph, and the accent starburst CTA. A heavy hairline rule
/// beneath separates it from the remaining sections. The engine keeps the lead out
/// of ``BriefViewModel/sections``, so it is never duplicated downstream.
struct BriefLeadView: View {
    /// The presentation-ready lead entry from ``BriefRenderer``.
    let lead: BriefViewModel.Entry
    /// The lead's call-to-action label (e.g. "Let's do it"); falls back when absent.
    let ctaLabel: String
    /// The edition's accent, sampled from its hero painting; defaults to the golden accent.
    var accent: Color = DaybriefTheme.accent
    /// Whether the CTA badge may use the macOS 26 Liquid Glass rendering. The offscreen
    /// snapshot tool sets this `false` (`ImageRenderer` can't rasterize Liquid Glass).
    var usesGlassCTA: Bool = true
    /// Called with the lead entry's id when the user dismisses it. Defaults to a no-op
    /// so snapshots and previews need not supply one.
    var onDismiss: (UUID) -> Void = { _ in }

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lead")
                .font(DaybriefTheme.serifBody(10).weight(.semibold))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(accent)
                .padding(.bottom, 6)
                .accessibilityLabel("Lead story")

            Text(lead.headline)
                .font(DaybriefTheme.serifDisplay(24))
                .foregroundStyle(DaybriefTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                // Keep the headline clear of the top-right dismiss control.
                .padding(.trailing, 22)
                .accessibilityAddTraits(.isHeader)

            if let detail = lead.detail {
                Text(detail)
                    .font(DaybriefTheme.serifBody(14))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let link = lead.link {
                Button {
                    openURL(link)
                } label: {
                    ActionBadge(label: ctaLabel, accent: accent, forcesFallback: !usesGlassCTA)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ctaLabel): \(lead.headline)")
                .accessibilityHint(lead.linkLabel.map { "Opens \($0)" } ?? "Opens the source")
                .padding(.top, 12)
            }

            // A heavier rule than the inter-entry hairline, setting the lead apart
            // from the sections that follow.
            Rectangle()
                .fill(DaybriefTheme.ink.opacity(0.18))
                .frame(height: 2)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A subtle dismiss control in the top-right corner of the lead card.
        .overlay(alignment: .topTrailing) {
            DismissCardButton(accessibilityLabel: "Dismiss lead story: \(lead.headline)") {
                onDismiss(lead.id)
            }
        }
    }
}
