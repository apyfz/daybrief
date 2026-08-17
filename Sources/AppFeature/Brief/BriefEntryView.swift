import BriefRender
import DaybriefCore
import SwiftUI

/// A single editorial item: a serif headline and a paragraph of context written as if
/// the assistant has read the source threads.
///
/// **Actionable entries are the card itself.** There is no CTA badge: when the model
/// gave an entry a `ctaLabel` — its judgement that there's something for the reader to
/// do — the whole card opens the source link, with a hover highlight to advertise it.
/// Informational entries (a routine receipt, an automated renewal) carry no label and
/// stay inert, so the brief stops offering a button on things it just said need no
/// action.
struct BriefEntryView: View {
    /// The presentation-ready entry from ``BriefRenderer``.
    let entry: BriefViewModel.Entry
    /// The model's call-to-action label, or `nil` when the entry is informational.
    /// Not printed anywhere — it's the signal for whether the card is actionable, and
    /// it phrases the accessibility hint.
    let ctaLabel: String?
    /// The edition's accent, sampled from its hero painting; defaults to the golden accent.
    var accent: Color = DaybriefTheme.accent
    /// Called with the entry's id when the user dismisses it. Defaults to a no-op so
    /// snapshots and previews need not supply one.
    var onDismiss: (UUID) -> Void = { _ in }

    @Environment(\.openURL) private var openURL
    @State private var isHovering = false

    /// Where a click on this card goes — `nil` when the entry isn't actionable.
    private var destination: URL? {
        guard ctaLabel != nil else { return nil }
        return entry.link
    }

    var body: some View {
        card
            // The dismiss control sits above the card's own click target, so dismissing
            // never opens the link.
            .overlay(alignment: .topTrailing) {
                DismissCardButton(accessibilityLabel: "Dismiss: \(entry.headline)") {
                    onDismiss(entry.id)
                }
            }
    }

    @ViewBuilder
    private var card: some View {
        if let destination {
            Button {
                openURL(destination)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            // A link cursor is the macOS convention for "this whole surface opens
            // something"; without it a card with no badge reads as inert. `pointerStyle`
            // rather than pushing/popping `NSCursor` — the cursor stack goes wrong if a
            // view disappears mid-hover (a dismissed card, a collapsed section).
            .pointerStyle(.link)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isLink)
            .accessibilityLabel(entry.headline)
            .accessibilityHint(ctaLabel.map { "\($0). Opens \(entry.linkLabel ?? "the source")" }
                ?? "Opens the source")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.headline)
                .font(DaybriefTheme.serifDisplay(18))
                .foregroundStyle(DaybriefTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                // Keep the headline clear of the top-right dismiss control.
                .padding(.trailing, 20)

            if let detail = entry.detail {
                // Body copy is set in the Geist sans (the headline stays serif), with a
                // little extra leading so the paragraph reads easily.
                Text(detail)
                    .font(DaybriefTheme.sansBody(11.5))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The hover highlight bleeds outside the text bounds via a negatively-padded
        // background, so it reads as a card without adding padding that would shift the
        // column's flush-left rhythm.
        .background {
            if destination != nil {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(isHovering ? 0.16 : 0))
                    .padding(-8)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
