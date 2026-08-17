import DaybriefCore
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

/// The app's icon set: real brand marks rather than SF Symbols, so a connector reads
/// as *itself* — Slack's lozenge, Gmail's M, Notion's cube, Calendar's 31.
///
/// The brand marks are filled silhouettes from Simple Icons (CC0) and Bootstrap Icons
/// (MIT, for Slack — Simple Icons dropped it on a trademark request). The two channel
/// markers are Hugeicons (free MIT set), which is stroke-only; there is no meaningful
/// "filled" hash, and neither Hugeicons' free tier nor Lucide ships filled variants.
///
/// Every connector glyph in the app routes through ``connector(_:)``. Before this
/// existed the mapping was copy-pasted across five call sites (the brief's source
/// dropdowns, Settings, onboarding's Assign Spaces, and the connector detail screens),
/// which is how Slack ended up as a bare `#`.
///
/// The assets are vector PDFs in `Bundle.module/Icons`, loaded as template images so
/// they take `foregroundStyle` like an SF Symbol and stay crisp at any size. A filled
/// mark is a silhouette with cut-outs (Notion's N, Calendar's 31), so those holes show
/// whatever sits behind the glyph rather than a second ink color.
public enum DaybriefIcon {
    /// Slack's lozenge mark.
    public static var slack: Image { asset("slack") }
    /// Notion's cube.
    public static var notion: Image { asset("notion") }
    /// Gmail's M.
    public static var mail: Image { asset("gmail") }
    /// Google Calendar's dated page.
    public static var calendar: Image { asset("gcal") }
    /// A `#`, for a public Slack channel.
    public static var hash: Image { asset("hash") }
    /// A padlock, for a private Slack channel.
    public static var lock: Image { asset("lock") }

    /// The glyph for `connector` — its brand mark where the free set has one.
    ///
    /// Falls back to the mail glyph for anything unrecognized, which only happens if a
    /// new connector ships without an icon.
    public static func connector(_ connector: ConnectorID) -> Image {
        switch connector.rawValue {
        case "slack": slack
        case "notion": notion
        case "gmail": mail
        case "gcal": calendar
        default: mail
        }
    }

    /// Loads a vector PDF from `Bundle.module/Icons` as a template image.
    ///
    /// Falls back to an SF Symbol if the resource is missing, so a packaging mistake
    /// shows a placeholder rather than an invisible button.
    private static func asset(_ name: String) -> Image {
        #if canImport(AppKit)
            if let cached = cache.object(forKey: name as NSString) {
                return Image(nsImage: cached)
            }
            guard let url = Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Icons"),
                  let image = NSImage(contentsOf: url)
            else {
                return Image(systemName: "square.dashed")
            }
            // Template rendering is what lets `foregroundStyle` tint the glyph.
            image.isTemplate = true
            cache.setObject(image, forKey: name as NSString)
            return Image(nsImage: image)
        #else
            return Image(systemName: "square.dashed")
        #endif
    }

    #if canImport(AppKit)
        /// Decoded icons, kept so a redrawing list doesn't re-read a PDF off disk per
        /// row. `NSCache` is documented thread-safe; the type isn't marked `Sendable`,
        /// so opt out explicitly for this shared instance (as `DaybriefTheme` does for
        /// its shared formatter).
        private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()
    #endif
}

public extension Image {
    /// Sizes an icon to `size` square, fitting its aspect ratio.
    ///
    /// Hugeicons are drawn on a 24×24 grid and load at their natural size, so unlike an
    /// SF Symbol they don't respond to `.font(.system(size:))` — they need an explicit
    /// frame.
    func daybriefIcon(size: CGFloat) -> some View {
        resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
