import BriefRender
import DaybriefCore
import SwiftUI

/// A titled "movement" of the brief — a small italic serif section title
/// (e.g. "Push your work forward") above its ordered entries, separated by a
/// hairline rule between entries like a set column of type.
///
/// `ctaLabels` carries the per-entry CTA text (from the original ``Brief``,
/// which the projected view model drops) keyed by entry id, so the badge prints
/// the LLM's chosen label — and is omitted entirely when it wrote none.
struct BriefSectionView: View {
    /// The presentation-ready section from ``BriefRenderer``.
    let section: BriefViewModel.Section
    /// Per-entry CTA labels keyed by entry id. A missing key means no action badge.
    let ctaLabels: [UUID: String]
    /// The edition's accent, sampled from its hero painting; defaults to the golden accent.
    var accent: Color = DaybriefTheme.accent
    /// Forwarded to each entry: called with the entry's id when the user dismisses it.
    /// Defaults to a no-op so snapshots and previews need not supply one.
    var onDismiss: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(DaybriefTheme.serifItalic(13))
                .foregroundStyle(DaybriefTheme.ink)
                .tracking(0.3)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(DaybriefTheme.ink.opacity(0.10))
                        .frame(height: 1)
                        .padding(.vertical, 14)
                }
                BriefEntryView(
                    entry: entry,
                    ctaLabel: ctaLabels[entry.id],
                    accent: accent,
                    onDismiss: onDismiss
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
