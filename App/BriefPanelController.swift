import AppFeature
import AppKit
import DaybriefUI
import SwiftUI

/// Owns the menu-bar status item and the floating brief panel, replacing
/// `MenuBarExtra(.window)`.
///
/// Why not `MenuBarExtra`: that scene hosts the panel in a system popover whose
/// content area is filled by the system's Liquid-Glass backing (not the window's
/// `backgroundColor`), and it repositions / re-lays-out that window on open and on
/// every content-height change — a second layout authority that fought our pinning.
///
/// Here WE own the window: a borderless `NSPanel` whose `contentView` is an
/// `NSGlassEffectView` (the macOS 26 Liquid Glass material) embedding the SwiftUI
/// card, so the panel refracts the desktop/windows behind it. We pin it to the
/// **right edge** of the screen (like Notification Center / CleanMyMac), a small gap
/// below the menu bar, regardless of where the menu-bar icon sits.
@MainActor
final class BriefPanelController: NSObject, NSWindowDelegate {
    /// The desktop-visible gap between the menu bar and the top of the card.
    private let gap: CGFloat = 10
    /// The gap between the right edge of the card and the right edge of the screen
    /// (matches the inset Notification Center / CleanMyMac use).
    private let rightMargin: CGFloat = 12
    /// The card's content width (matches `BriefPanelView.panelWidth`).
    private let cardWidth: CGFloat = 380
    /// The card's corner radius (matches the SwiftUI content clip + glass mask).
    private let cornerRadius: CGFloat = 16

    private let model: AppModel
    /// Opens the setup / settings window. Injected from the app layer because a
    /// detached `NSHostingView` can't reach SwiftUI's scene-connected `openWindow`.
    private let openSettings: () -> Void

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    /// Last height SwiftUI reported for the card; drives the panel height.
    private var measuredCardHeight: CGFloat = 0
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
    }

    // MARK: - Status item

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Daybrief")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
    }

    @objc private func togglePanel() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    /// Shows the panel from outside a click (e.g. the widget's `daybrief://` deep link).
    func presentPanel() {
        guard panel?.isVisible != true else { return }
        show()
    }

    // MARK: - Show / hide

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        layoutAndPin()
        // Key (not active): the card's buttons/scrolling work on the first click and
        // Esc reaches us, but the app stays an accessory and doesn't steal activation.
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
        statusItem?.button?.highlight(true)
    }

    func hide() {
        panel?.orderOut(nil)
        removeDismissMonitors()
        statusItem?.button?.highlight(false)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu // above normal windows, like a menu-bar dropdown
        // The window stays clear / non-opaque so the rounded-corner triangles show the
        // desktop, but the masked glass contentView now drives a NATIVE rounded window
        // shadow (hasShadow = true). Do NOT set isOpaque = true — it would paint the
        // clear corners black and square off the shadow.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self

        // The SwiftUI card. It rides INSIDE the Liquid Glass: NO surface glass, NO
        // outer shadow, NO transparent inset (the window + glass own those now). The
        // host must be transparent so the glass shows through the header strip and the
        // margins around the paper sheet — an opaque host backing is exactly the old
        // flat look.
        let host = NSHostingView(
            rootView: AnyView(
                BriefPanelView(
                    model: model,
                    onClose: { [weak self] in self?.hide() },
                    onOpenSettings: { [weak self] in self?.openSettings() },
                    onContentHeightChange: { [weak self] height in self?.cardHeightChanged(height) }
                )
            )
        )
        host.sizingOptions = [] // we size the window; SwiftUI fills it
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        // Light Liquid Glass backing: a content-free clear NSGlassEffectView (no tint,
        // default light appearance) as the background layer, with the warm paper card
        // floating above it as a transparent sibling — so the glass reads in the margins
        // and header strip while the reading surface stays paper.
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = cornerRadius

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = container

        // Glass = backmost full-bounds layer; the SwiftUI card rides above it.
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)

        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: glass)

        return panel
    }

    /// SwiftUI reported a new card height (hero image load, refresh swap). Re-pin so
    /// the top edge stays `gap` below the menu bar and the panel grows downward.
    private func cardHeightChanged(_ height: CGFloat) {
        guard height > 0, height != measuredCardHeight else { return }
        measuredCardHeight = height
        if panel?.isVisible == true { layoutAndPin() }
    }

    // MARK: - Positioning

    /// Pin the window so the card's top edge sits `gap` below the menu bar and its
    /// right edge sits `rightMargin` from the screen's right edge. The window now IS
    /// the card (the native shadow lives outside the frame), so there is no inset
    /// math. Idempotent: derived from fixed screen geometry every call, the
    /// `frame == newFrame` guard prevents thrash, and nothing else sets the frame.
    private func layoutAndPin() {
        guard
            let panel,
            let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        else { return }

        let vis = screen.visibleFrame
        let windowWidth = cardWidth
        let windowHeight = measuredCardHeight > 0 ? measuredCardHeight : 500

        // `vis.maxY` is just below the menu bar (notch-safe — visibleFrame already
        // excludes the menu-bar band). Card top sits `gap` below it; the window == card.
        var originY = (vis.maxY - gap) - windowHeight
        originY = max(originY, vis.minY) // keep the card bottom on-screen

        // Pin the card's right edge `rightMargin` from the screen's right edge.
        let originX = (vis.maxX - rightMargin) - windowWidth

        let newFrame = NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
        guard panel.frame != newFrame else { return }
        panel.setFrame(newFrame, display: true)
        // Recompute the native shadow against the new bounds so it doesn't lag the resize.
        panel.invalidateShadow()
    }

    // MARK: - Dismiss-on-outside-click / Esc

    private func installDismissMonitors() {
        // Clicks in another app (or the desktop) dismiss the panel.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Clicks inside our own process: pass through clicks on the panel and the
        // status button (the button's action toggles); dismiss on any other click.
        // Esc closes.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.hide(); return nil } // Esc
                return event
            }
            // Let the status button handle its own toggle click.
            if event.window == self.statusItem?.button?.window { return event }
            if event.window != self.panel { self.hide() }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
}
