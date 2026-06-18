import DaybriefCore
import SwiftUI

/// The top "plate" of the edition: the public-domain hero painting with the
/// masthead set over it, a tiny credit line beneath, and the two vertical
/// periodical rails (the dateline on the left spine, the generation time on the
/// right spine) running alongside — matching the design reference.
struct BriefHeroHeaderView: View {
    /// The hero artwork for this edition, or `nil` to fall back to a warm placeholder.
    let hero: HeroArtwork?
    /// The masthead text, e.g. "The Wednesday Brief".
    let masthead: String
    /// The dateline shown on the left spine, e.g. "17 JUN 2026".
    let dateline: String
    /// The generation time shown on the right spine, e.g. "05:32 AM".
    let generationTime: String
    /// The edition's accent, sampled from its hero painting; defaults to the golden accent.
    var accent: Color = DaybriefTheme.accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VerticalRailView(text: dateline, edge: .leading)

            VStack(spacing: 8) {
                ZStack {
                    HeroArtworkView(hero)
                        .frame(height: 188)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            // An always-on darkening overlay so the golden masthead reads
                            // cleanly over ANY painting — including busy mid-tone ones
                            // (e.g. the Cézanne) where a top/bottom-only scrim left the
                            // center too bright. A uniform tint plus a little extra at the
                            // edges for depth.
                            ZStack {
                                Color.black.opacity(0.34)
                                LinearGradient(
                                    colors: [.black.opacity(0.25), .clear, .black.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(DaybriefTheme.ink.opacity(0.08), lineWidth: 1)
                        )

                    if !masthead.isEmpty {
                        BriefMastheadView(masthead: masthead, accent: accent)
                    }
                }
                // Just the artwork — no visible credit line. (Met open-access works are
                // CC0/public-domain, so no attribution is required; the credit metadata
                // stays on `HeroArtwork` for the archive but isn't shown in the panel.)
            }

            VerticalRailView(text: generationTime, edge: .trailing)
        }
    }
}

/// A thin vertical spine annotation — text rotated 90° as in the margins of a
/// printed periodical. Reads bottom-to-top on the left, top-to-bottom on the right.
struct VerticalRailView: View {
    /// The rail text (a dateline or a time).
    let text: String
    /// Which margin this rail sits in, which sets the rotation direction.
    let edge: HorizontalEdge

    var body: some View {
        Text(text)
            .font(DaybriefTheme.serifBody(11))
            .tracking(1.5)
            .foregroundStyle(DaybriefTheme.inkSecondary)
            .fixedSize()
            .rotationEffect(.degrees(edge == .leading ? -90 : 90))
            .frame(width: 16)
            .frame(maxHeight: .infinity, alignment: .center)
            .accessibilityLabel(text)
    }
}
