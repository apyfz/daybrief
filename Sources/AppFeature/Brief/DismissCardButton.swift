import SwiftUI

/// A small, deliberately quiet close affordance for an individual brief card — a
/// ~10pt secondary-ink `xmark` as a plain button — used to dismiss the lead story
/// and section entries once the user has dealt with them.
///
/// It is a *dismiss* affordance, not a primary action, so it stays visually subdued
/// (no glass, no accent, no fill) and sits in the top-right corner of the card it
/// closes. The owning card supplies an accessible label naming what gets dismissed.
struct DismissCardButton: View {
    /// The accessibility label, e.g. "Dismiss: <headline>".
    let accessibilityLabel: String
    /// Invoked when the user taps the close control.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                // Keep a comfortable hit target without enlarging the visible glyph.
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
