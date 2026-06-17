import BriefRender
import DaybriefCore
import SwiftUI

/// A titled "movement" of the brief — a small italic serif section title
/// (e.g. "Push your work forward") above its ordered entries, separated by a
/// hairline rule between entries like a set column of type.
///
/// `ctaLabels` carries the per-entry CTA text (from the original ``Brief``,
/// which the projected view model drops) keyed by entry id, so the badge prints
/// the LLM's chosen label and falls back to "Let's do it" when absent.
struct BriefSectionView: View {
    /// The presentation-ready section from ``BriefRenderer``.
    let section: BriefViewModel.Section
    /// Per-entry CTA labels keyed by entry id; missing keys fall back to the default.
    let ctaLabels: [UUID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(DaybriefTheme.serifBody(13).italic())
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
                    ctaLabel: ctaLabels[entry.id] ?? "Let's do it"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
