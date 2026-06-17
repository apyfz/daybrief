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

// MARK: - Hex color

public extension Color {
    /// Parses a `#RRGGBB` / `RRGGBB` hex string into a `Color`, returning `nil` for any
    /// other length or non-hex input.
    ///
    /// Used for the per-edition accent sampled from each hero painting
    /// (``DaybriefCore/HeroArtwork/accentHex``): `DaybriefCore` carries no color type, so
    /// the curated hex travels as a string and the UI converts it here. Only the 6-digit
    /// RGB form is accepted (an optional single leading `#`); anything else falls back to
    /// `DaybriefTheme/accent` at the call site.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
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
    /// The starburst fill — the edition's per-edition accent, sampled from its hero
    /// painting; defaults to the app's golden accent.
    private let accent: Color

    /// Creates an action badge with `label`, optionally tinted by the edition `accent`.
    public init(label: String, accent: Color = DaybriefTheme.accent) {
        self.label = label
        self.accent = accent
    }

    public var body: some View {
        Text("\(label) →")
            .font(DaybriefTheme.serifBody(11).weight(.semibold))
            .foregroundStyle(DaybriefTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(StarburstShape().fill(accent))
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

    /// A calm default painting shown when an edition has no (resolvable) hero — so the
    /// plate always carries real art rather than a placeholder. (An older brief saved
    /// before tone-matched art, or a renamed asset, would otherwise have no image.)
    private static let defaultArtworkName = "pissarro-tuileries-winter"

    public var body: some View {
        if let image = resolvedImage {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel(hero?.creditLine ?? "Edition artwork")
        } else {
            placeholder
        }
    }

    /// The edition's painting if it resolves, otherwise a calm bundled default — so
    /// the hero never renders as a broken image.
    private var resolvedImage: Image? {
        if let hero, let image = bundledImage(named: hero.assetName) {
            return image
        }
        return bundledImage(named: Self.defaultArtworkName)
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

    /// A warm, classical-feeling plate used only if even the default painting can't
    /// be loaded — intentional and calm, never a broken-image glyph.
    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DaybriefTheme.accent.opacity(0.38),
                    DaybriefTheme.paper,
                    DaybriefTheme.accent.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.black.opacity(0.06), .clear],
                center: .center,
                startRadius: 8,
                endRadius: 260
            )
        }
        .accessibilityLabel("Edition artwork")
    }
}
