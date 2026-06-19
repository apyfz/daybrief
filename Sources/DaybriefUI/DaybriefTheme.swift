import CoreText
import DaybriefCore
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

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

    // MARK: - Bundled font registration

    /// The PostScript name of the bundled upright editorial serif.
    private static let tiemposRegularName = "TiemposText-Regular"
    /// The PostScript name of the bundled italic editorial serif.
    private static let tiemposItalicName = "TiemposText-RegularItalic"
    /// The PostScript name of the bundled body sans (Geist, regular weight).
    private static let geistRegularName = "Geist-Regular"
    /// The PostScript name of the bundled body sans (Geist, medium weight).
    private static let geistMediumName = "Geist-Medium"

    /// Guards ``registerBundledFonts()`` so the registration only ever runs once,
    /// no matter how many times (or how early) callers invoke it.
    private static let registerOnce: Void = {
        #if canImport(AppKit)
            let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
            for url in urls {
                // `.process` registers for this process only (no user font install).
                // Re-registering an already-registered font returns an error we
                // intentionally ignore — registration is idempotent.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        #endif
    }()

    /// Registers every bundled `.ttf` in `Bundle.module/Fonts` for this process so the
    /// editorial serif is available before any view renders.
    ///
    /// Idempotent and run-once (backed by a `static let`), and safe to call lazily:
    /// the type APIs below call it before probing for the font. When the licensed
    /// Tiempos files are absent (they are git-ignored), this is a no-op and the type
    /// scale falls back to the system serif.
    public static func registerBundledFonts() {
        _ = registerOnce
    }

    /// Whether the bundled Tiempos Text serif is actually available, computed once
    /// *after* registering the bundled fonts. Drives the type APIs' fallback.
    private static let tiemposAvailable: Bool = {
        registerBundledFonts()
        #if canImport(AppKit)
            return NSFont(name: tiemposRegularName, size: 12) != nil
        #else
            return false
        #endif
    }()

    /// Whether the bundled Geist sans is available, computed once after registering
    /// the bundled fonts. Drives ``sansBody(_:)`` / ``sansMedium(_:)`` fallback.
    private static let geistAvailable: Bool = {
        registerBundledFonts()
        #if canImport(AppKit)
            return NSFont(name: geistRegularName, size: 12) != nil
        #else
            return false
        #endif
    }()

    // MARK: - Type

    /// A serif display font (masthead, headlines, lede) at `size`.
    ///
    /// Prefers the bundled Tiempos Text serif when present, scaling relative to
    /// `.title` for Dynamic Type; otherwise falls back to the system serif (New York
    /// on macOS 26) with a slightly heavier weight for the masthead's printed-title
    /// presence, so no font has to be bundled.
    public static func serifDisplay(_ size: CGFloat) -> Font {
        if tiemposAvailable {
            return .custom(tiemposRegularName, size: size, relativeTo: .title)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    /// A quiet serif body font for context paragraphs and captions at `size`.
    ///
    /// Prefers the bundled Tiempos Text serif (scaled relative to `.body`); otherwise
    /// falls back to the regular system serif.
    public static func serifBody(_ size: CGFloat) -> Font {
        if tiemposAvailable {
            return .custom(tiemposRegularName, size: size, relativeTo: .body)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    /// An italic serif at `size`, using the real Tiempos Text italic face when bundled
    /// (synthesised obliquing of the upright face reads noticeably worse); otherwise
    /// falls back to the system serif obliqued via `.italic()`.
    ///
    /// Use this anywhere the editorial serif is set in italic (the lede, the masthead's
    /// leading "The", the quiet-day line) rather than `serifDisplay(_:).italic()`.
    public static func serifItalic(_ size: CGFloat) -> Font {
        if tiemposAvailable {
            return .custom(tiemposItalicName, size: size, relativeTo: .body)
        }
        return .system(size: size, design: .serif).italic()
    }

    /// The body-copy sans (Geist) at `size`, for the running context paragraphs
    /// where a clean humanist sans reads more easily than the serif at small sizes
    /// (the headlines, masthead, lede, and section titles stay in the serif).
    ///
    /// Prefers the bundled Geist (scaled relative to `.body`); otherwise falls back to
    /// the regular system sans, so nothing has to be bundled.
    public static func sansBody(_ size: CGFloat) -> Font {
        if geistAvailable {
            return .custom(geistRegularName, size: size, relativeTo: .body)
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    /// The medium-weight body sans (Geist Medium) at `size`, for emphasis within body
    /// copy (e.g. link labels). Falls back to the system sans at `.medium` weight.
    public static func sansMedium(_ size: CGFloat) -> Font {
        if geistAvailable {
            return .custom(geistMediumName, size: size, relativeTo: .body)
        }
        return .system(size: size, weight: .medium, design: .default)
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

// MARK: - Paper sheet

/// The warm-paper "sheet" that the editorial reading surface (hero, lede, lead,
/// sections, colophon — and the welcome / empty / loading / error states) floats on
/// when the surrounding panel chrome is Liquid Glass (macOS 26).
///
/// Text reads on opaque warm paper for legibility while the panel margins read as
/// glass; on pre-26 systems the panel is already paper, so the sheet just adds a
/// gentle rounded edge and shadow and is visually quiet.
public extension View {
    /// Wraps the editorial content in the warm-paper sheet (rounded, subtly shadowed).
    func paperSheet(cornerRadius: CGFloat = 16) -> some View {
        modifier(PaperSheet(cornerRadius: cornerRadius))
    }
}

/// The view modifier backing ``SwiftUICore/View/paperSheet(cornerRadius:)``.
private struct PaperSheet: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // Opaque, readable warm page — the brief's literary reading surface.
                    .fill(DaybriefTheme.paper)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // A bright top-to-bottom rim sheen so the page reads as a glass-edged card
            // floating on the desktop, not a flat rectangle.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.6), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
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

/// The call-to-action badge from the design reference (e.g. "Let's do it →"): on
/// macOS 26 an accent-tinted **interactive Liquid Glass** capsule with the label
/// set in a small serif and a trailing chevron; on earlier systems the original
/// playful golden "starburst" — a hand-drawn-feeling burst of the accent color
/// with the label over it. Decorative chrome — the tap target is the enclosing
/// button.
public struct ActionBadge: View {
    /// The CTA text to print on the badge (the trailing chevron is added here).
    private let label: String
    /// The capsule tint / starburst fill — the edition's per-edition accent, sampled
    /// from its hero painting; defaults to the app's golden accent.
    private let accent: Color
    /// Forces the non-glass starburst rendering even on macOS 26. Used by the
    /// offscreen snapshot tool: `ImageRenderer` does not rasterize the Liquid Glass
    /// material, so a glass badge would snapshot blank.
    private let forcesFallback: Bool

    /// Creates an action badge with `label`, optionally tinted by the edition `accent`.
    ///
    /// Set `forcesFallback` to render the non-glass starburst even on macOS 26 (for
    /// `ImageRenderer`-based snapshots, which can't rasterize Liquid Glass).
    public init(label: String, accent: Color = DaybriefTheme.accent, forcesFallback: Bool = false) {
        self.label = label
        self.accent = accent
        self.forcesFallback = forcesFallback
    }

    public var body: some View {
        if #available(macOS 26.0, *), !forcesFallback {
            glassBadge
        } else {
            starburstBadge
        }
    }

    /// The macOS 26 Liquid Glass treatment: an accent-tinted interactive glass
    /// capsule. The label stays ink for legibility against the tinted glass.
    @available(macOS 26.0, *)
    private var glassBadge: some View {
        HStack(spacing: 4) {
            Text(label)
            Image(systemName: "chevron.right")
                .font(DaybriefTheme.serifBody(10).weight(.semibold))
        }
        .font(DaybriefTheme.serifBody(11).weight(.semibold))
        .foregroundStyle(DaybriefTheme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(accent).interactive(), in: .capsule)
        .accessibilityHidden(true)
    }

    /// The pre-26 fallback: the original golden starburst badge.
    private var starburstBadge: some View {
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
