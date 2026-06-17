import SwiftUI

/// The colophon: a quiet, print-style provenance footer at the very foot of the
/// edition, e.g. "FILED 7:02 AM · 14 SIGNALS READ, 4 SURFACED · GMAIL · CALENDAR".
///
/// It replaces the old relative-time footer with something factual and editorial:
/// small, muted, and set in letterspaced small caps like the imprint line on a
/// printed page. The string itself is computed at assembly by ``BriefRender`` (never
/// by the model); this view only sets it (design §brief-design-language, "colophon").
struct BriefColophonView: View {
    /// The pre-computed colophon line from ``BriefRender/BriefViewModel/colophon``.
    let colophon: String

    var body: some View {
        Text(colophon)
            .font(DaybriefTheme.serifBody(10))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(DaybriefTheme.inkSecondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Colophon: \(colophon)")
    }
}
