import DaybriefCore
import SwiftUI

/// The Daybrief design system: a warm, editorial palette and a classic serif type
/// scale that make the brief feel like a printed morning periodical rather than a
/// dashboard. See `docs/design/brief-design-language.md`.
///
/// Every color and font used by the SwiftUI layer routes through here so the look
/// stays consistent across the brief panel, onboarding, and settings, and can be
/// retuned in one place.
public enum DaybriefTheme {
    /// The warm cream / off-white page background (`~#FAF7F0`).
    public static let paper = Color(red: 0.980, green: 0.969, blue: 0.941)

    /// The primary text color: a muted, warm near-black (kept off pure black so it
    /// reads like ink on paper, not UI chrome).
    public static let ink = Color(red: 0.149, green: 0.137, blue: 0.118)

    /// Secondary text: a muted warm gray for context, captions, and rails.
    public static let inkSecondary = Color(red: 0.420, green: 0.404, blue: 0.380)

    /// The golden-yellow accent (`~#F2C200`) — the masthead, CTA badges, dots.
    public static let accent = Color(red: 0.949, green: 0.761, blue: 0.000)

    // MARK: - Type

    /// A serif display font (masthead, headlines, lede) at `size`.
    ///
    /// Uses the system serif (New York on macOS 26) so no font has to be bundled;
    /// a slightly heavier weight gives the masthead its printed-title presence.
    public static func serifDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// A quiet serif body font for context paragraphs and captions at `size`.
    public static func serifBody(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

// MARK: - Editorial card

/// The shared soft-rounded card chrome used to set a section of the brief (and the
/// settings/onboarding cards): a gentle fill over the paper with a hairline border
/// and a soft drop shadow, like a card laid on a page.
public extension View {
    /// Wraps the view in the standard Daybrief editorial card surface.
    func editorialCard() -> some View {
        modifier(EditorialCard())
    }
}

/// The view modifier backing ``SwiftUICore/View/editorialCard()``.
private struct EditorialCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DaybriefTheme.ink.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: DaybriefTheme.ink.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - Action badge

/// The playful golden "starburst" call-to-action badge from the design reference
/// (e.g. "Let's do it →"): a hand-drawn-feeling burst of the accent color with the
/// label set in a small serif over it. Decorative chrome — the tap target is the
/// enclosing button.
public struct ActionBadge: View {
    /// The CTA text to print on the badge (the trailing arrow is added here).
    private let label: String

    /// Creates an action badge with `label`.
    public init(label: String) {
        self.label = label
    }

    public var body: some View {
        Text("\(label) →")
            .font(DaybriefTheme.serifBody(11).weight(.semibold))
            .foregroundStyle(DaybriefTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(StarburstShape().fill(DaybriefTheme.accent))
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }
}

/// A simple many-pointed starburst, used behind the CTA label.
private struct StarburstShape: Shape {
    /// How many points the burst has.
    var points: Int = 14
    /// How far the inner notches sit relative to the outer tips (0…1).
    var innerRatio: CGFloat = 0.86

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = CGSize(width: rect.width / 2, height: rect.height / 2)
        let inner = CGSize(width: outer.width * innerRatio, height: outer.height * innerRatio)

        var path = Path()
        let step = Double.pi / Double(points)
        for i in 0 ..< (points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * step - Double.pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius.width,
                y: center.y + CGFloat(sin(angle)) * radius.height
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Hero artwork

/// Renders a brief edition's public-domain hero painting from the app bundle, with
/// a graceful warm placeholder when the image asset is missing (so the panel never
/// shows a broken image while the curated `.imageset`s are being added).
public struct HeroArtworkView: View {
    /// The hero artwork to render, or `nil` for the placeholder.
    private let hero: HeroArtwork?

    /// Creates a hero artwork view for `hero`.
    public init(_ hero: HeroArtwork?) {
        self.hero = hero
    }

    public var body: some View {
        if let hero, let image = bundledImage(named: hero.assetName) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel(hero.creditLine)
        } else {
            placeholder
        }
    }

    /// Loads `name` from the app bundle's asset catalog, if present.
    private func bundledImage(named name: String) -> Image? {
        #if canImport(AppKit)
            guard !name.isEmpty, let nsImage = NSImage(named: name) else { return nil }
            return Image(nsImage: nsImage)
        #else
            return nil
        #endif
    }

    /// A calm, classical-feeling gradient stand-in when no painting is bundled.
    private var placeholder: some View {
        LinearGradient(
            colors: [
                DaybriefTheme.accent.opacity(0.45),
                DaybriefTheme.paper,
                DaybriefTheme.inkSecondary.opacity(0.25),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "photo.artframe")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DaybriefTheme.ink.opacity(0.25))
        )
        .accessibilityLabel("Edition artwork")
    }
}
