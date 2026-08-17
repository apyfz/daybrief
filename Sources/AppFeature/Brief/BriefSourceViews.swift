import BriefRender
import DaybriefCore
import SwiftUI

/// The headline **"Daybrief"** card: a holistic summary of everything collected today,
/// across all sources. Replaces the old single "lead story" — the name finally pays off.
struct DaybriefSummaryCard: View {
    /// The holistic overview prose from ``BriefViewModel/summary``.
    let summary: String
    /// The edition's accent (the golden default).
    var accent: Color = DaybriefTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daybrief")
                .font(DaybriefTheme.serifDisplay(20))
                .foregroundStyle(accent)
            Text(summary)
                .font(DaybriefTheme.serifBody(15))
                .foregroundStyle(DaybriefTheme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .editorialCard()
    }
}

/// One connector's updates as a **collapsible dropdown**: a header (source glyph + name
/// + count) that toggles open to reveal the source's entry cards. Collapsed by default so
/// the brief reads as the Daybrief summary plus a tidy list of sources to open.
struct BriefSourceDropdown: View {
    /// The presentation-ready section (one connector's entries).
    let section: BriefViewModel.Section
    /// Per-entry CTA labels keyed by entry id. A missing key means the model judged the
    /// entry informational, so its card isn't clickable.
    let ctaLabels: [UUID: String]
    /// The edition's accent.
    var accent: Color = DaybriefTheme.accent
    /// Called with the entry's id when the user dismisses it.
    var onDismiss: (UUID) -> Void = { _ in }

    @State private var expanded: Bool

    init(
        section: BriefViewModel.Section,
        ctaLabels: [UUID: String],
        accent: Color = DaybriefTheme.accent,
        startsExpanded: Bool = false,
        onDismiss: @escaping (UUID) -> Void = { _ in }
    ) {
        self.section = section
        self.ctaLabels = ctaLabels
        self.accent = accent
        self.onDismiss = onDismiss
        // The offscreen snapshot passes `true`: a page of collapsed headers isn't a
        // useful review of the editorial surface.
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { _, entry in
                        Rectangle()
                            .fill(DaybriefTheme.ink.opacity(0.10))
                            .frame(height: 1)
                            .padding(.vertical, 14)
                        BriefEntryView(
                            entry: entry,
                            ctaLabel: ctaLabels[entry.id],
                            accent: accent,
                            onDismiss: onDismiss
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .editorialCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            sourceIcon
                .daybriefIcon(size: 14)
                .foregroundStyle(DaybriefTheme.ink)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(DaybriefTheme.serifBody(15))
                    .foregroundStyle(DaybriefTheme.ink)
                if !expanded, let teaser = section.entries.first?.headline {
                    Text(teaser)
                        .font(DaybriefTheme.sansBody(11))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            Text("\(section.entries.count)")
                .font(DaybriefTheme.sansMedium(12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(DaybriefTheme.ink.opacity(0.06), in: Capsule())

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(section.title), \(section.entries.count) updates")
        .accessibilityHint(expanded ? "Collapse" : "Expand")
    }

    /// The connector glyph for the dropdown header.
    private var sourceIcon: Image {
        guard let source = section.source else { return DaybriefIcon.mail }
        return DaybriefIcon.connector(source)
    }
}
