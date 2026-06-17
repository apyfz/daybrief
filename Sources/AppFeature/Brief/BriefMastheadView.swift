import DaybriefCore
import SwiftUI

/// The edition masthead laid over the hero artwork: a newspaper-style title named
/// for the weekday, with the leading article ("The") in italic above the rest of
/// the title in large golden serif — exactly as in the design reference.
///
/// The masthead string comes from ``Brief/masthead`` (e.g. "The Wednesday Brief").
/// We split off a leading "The " so it can be set in italic, per the design language;
/// any other phrasing degrades gracefully to a single golden line.
struct BriefMastheadView: View {
    /// The full masthead text, e.g. "The Wednesday Brief".
    let masthead: String

    /// The italicized leading article, if the masthead begins with "The ".
    private var article: String? {
        masthead.hasPrefix("The ") ? "The" : nil
    }

    /// The roman remainder of the masthead (everything after the leading article).
    private var rest: String {
        guard article != nil else { return masthead }
        return String(masthead.dropFirst("The ".count))
    }

    var body: some View {
        VStack(alignment: .center, spacing: -6) {
            if let article {
                Text(article)
                    .font(DaybriefTheme.serifDisplay(30).italic())
                    .foregroundStyle(DaybriefTheme.accent)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
            }
            Text(rest)
                .font(DaybriefTheme.serifDisplay(48))
                .foregroundStyle(DaybriefTheme.accent)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(masthead)
    }
}
