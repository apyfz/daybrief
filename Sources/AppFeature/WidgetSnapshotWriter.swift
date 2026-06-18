import AppKit
import DaybriefCore
import os
import WidgetKit

/// Publishes a small, display-safe snapshot of the current brief into the shared App
/// Group container so the sandboxed desktop widget can render it, then asks WidgetKit
/// to reload.
///
/// The snapshot is the **full** ``DaybriefCore/Brief`` value (the persisted DB row
/// drops masthead / lede / lead / hero, so only the in-memory brief carries them) plus
/// a host-downsampled hero PNG. It contains only the already-redacted editorial fields
/// the panel itself shows — never OAuth tokens, the LLM key, the SQLCipher key, or raw
/// connector payloads. See `docs/build/widget.md` and `SECURITY.md`.
///
/// Best-effort and silent: the widget is non-critical, so every failure is logged, not
/// surfaced. A no-op on builds without the App Group (unit tests, the snapshot CLI).
enum WidgetSnapshotWriter {
    private static let logger = Logger(subsystem: "co.daybrief.app", category: "WidgetSnapshot")

    /// The calm default painting used when an edition has no resolvable hero — mirrors
    /// `HeroArtworkView`, so the widget shows the same art the panel would.
    private static let defaultArtworkName = "pissarro-tuileries-winter"

    /// Largest hero edge written to the container. Comfortably covers the large widget's
    /// hero at 2× while staying well under the widget's ~30 MB memory ceiling (full-res
    /// art would Jetsam-kill the extension).
    private static let maxHeroPixel: CGFloat = 1200

    /// Publishes `brief` (or clears the snapshot when `nil`) and reloads the widget.
    @MainActor
    static func publish(_ brief: Brief?) {
        // Skip entirely on non-App-Group builds (tests / snapshot tool): containerURL
        // is nil there, so there is nothing to write and no widget to reload.
        guard AppGroup.containerURL != nil else { return }
        if let brief {
            writeBrief(brief)
            writeHero(for: brief)
        } else {
            removeFile(AppGroup.FileName.latestBrief)
            removeFile(AppGroup.FileName.latestHero)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func writeBrief(_ brief: Brief) {
        guard let url = AppGroup.url(for: AppGroup.FileName.latestBrief) else { return }
        do {
            try JSONEncoder().encode(brief).write(to: url, options: .atomic)
        } catch {
            logger.error("snapshot brief write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func writeHero(for brief: Brief) {
        guard let url = AppGroup.url(for: AppGroup.FileName.latestHero) else { return }
        let name = brief.hero?.assetName ?? ""
        let image = NSImage(named: name) ?? NSImage(named: defaultArtworkName)
        guard let image, let png = downsampledPNG(image, maxPixel: maxHeroPixel) else {
            // No resolvable art → drop any stale hero so the widget uses its own fallback.
            removeFile(AppGroup.FileName.latestHero)
            return
        }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            logger.error("snapshot hero write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Renders `image` to a PNG no larger than `maxPixel` on its longest edge, in true
    /// pixels (so the hero stays crisp on Retina without shipping the full-res asset).
    @MainActor
    private static func downsampledPNG(_ image: NSImage, maxPixel: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxPixel / max(w, h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: tw, height: th)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private static func removeFile(_ name: String) {
        guard let url = AppGroup.url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
