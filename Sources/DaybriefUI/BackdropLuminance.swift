import AppKit
import SwiftUI

/// Samples the *wallpaper* luminance behind a screen rectangle, so chrome over clear
/// Liquid Glass can flip white-on-dark / dark-on-light the way the system menu bar
/// does. Permission-free: reads `NSWorkspace.desktopImageURL(for:)`, never screen
/// recording / TCC.
///
/// It only sees the wallpaper — not windows behind the panel (that needs
/// screen-recording permission). For a panel pinned near the top-right that is almost
/// always the desktop, which is the same trade-off the menu bar itself makes.
@MainActor
enum BackdropLuminance {
    /// Average perceived luminance (0…1) of the wallpaper under `rectInScreen`
    /// (screen-global, AppKit bottom-left origin), or `nil` if the wallpaper can't be
    /// read (no still URL, undecodable — e.g. an aerial/video) so the caller keeps its
    /// last value instead of flickering.
    static func averageLuminance(behind rectInScreen: CGRect, on screen: NSScreen) -> Double? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        guard let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let imgW = CGFloat(cg.width), imgH = CGFloat(cg.height)
        guard imgW > 0, imgH > 0 else { return nil }
        let scr = screen.frame

        // Default Tahoe wallpaper mode is Fill Screen: scale to cover, center-crop.
        let scale = max(scr.width / imgW, scr.height / imgH)
        let displayedW = imgW * scale, displayedH = imgH * scale
        let cropOffX = (displayedW - scr.width) / 2.0
        let cropOffY = (displayedH - scr.height) / 2.0

        // Screen-global (bottom-left) → this screen's top-left space (CGImage origin),
        // flipping Y via the rect's maxY.
        let localX = rectInScreen.minX - scr.minX
        let localYTop = scr.height - (rectInScreen.maxY - scr.minY)

        let srcRect = CGRect(
            x: (cropOffX + localX) / scale,
            y: (cropOffY + localYTop) / scale,
            width: rectInScreen.width / scale,
            height: rectInScreen.height / scale
        ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard !srcRect.isNull, srcRect.width >= 1, srcRect.height >= 1,
              let sub = cg.cropping(to: srcRect.integral) else { return nil }

        // Downsample to a tiny sRGB buffer and average Rec.709 luminance.
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(
            data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(sub, in: CGRect(x: 0, y: 0, width: n, height: n))

        var sum = 0.0
        for i in 0 ..< (n * n) {
            let r = Double(px[i * 4]) / 255.0
            let g = Double(px[i * 4 + 1]) / 255.0
            let b = Double(px[i * 4 + 2]) / 255.0
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return sum / Double(n * n)
    }
}

/// Observable backdrop state for chrome over clear Liquid Glass: owns
/// ``isDarkBackdrop`` and recomputes it from the wallpaper on the real system signals
/// (space switch, display change) plus a slow poll (there is no public
/// "wallpaper changed" notification).
@MainActor
@Observable
public final class BackdropMonitor {
    /// `true` → the wallpaper behind the header is dark → use a WHITE foreground.
    /// Safe default mirrors the menu bar at night.
    public private(set) var isDarkBackdrop: Bool = true

    /// Hysteresis around 0.5 so a mid-gray backdrop doesn't flicker the chrome.
    private let lower = 0.42
    private let upper = 0.58

    private var rectProvider: (() -> (rect: CGRect, screen: NSScreen)?)?
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    public init() {}

    /// Begins monitoring. `rectProvider` returns the current header-strip rect
    /// (screen-global) + its screen. Idempotent: re-calling re-binds cleanly.
    public func start(rectProvider: @escaping () -> (rect: CGRect, screen: NSScreen)?) {
        teardown()
        self.rectProvider = rectProvider

        let wsCenter = NSWorkspace.shared.notificationCenter
        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } })

        // No public "desktop picture changed" notification — poll slowly as a backstop.
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        recompute()
    }

    /// Recompute from the current header rect (call on show / re-pin / height change).
    public func recompute() {
        guard let (rect, screen) = rectProvider?() else { return }
        guard let lum = BackdropLuminance.averageLuminance(behind: rect, on: screen) else {
            return // unreadable wallpaper (aerial/video): keep last value
        }
        if isDarkBackdrop, lum > upper { isDarkBackdrop = false }
        else if !isDarkBackdrop, lum < lower { isDarkBackdrop = true }
    }

    /// Stops monitoring and tears down observers + timer (keeps the last value).
    public func stop() {
        teardown()
    }

    private func teardown() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            wsCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
