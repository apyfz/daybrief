import AppFeature
import AppKit
import os
import SwiftUI

/// Owns the long-lived app machinery: the activation policy (accessory, no Dock
/// icon), the bootstrap of the app-owned ``AppFeature/AppModel``, and the
/// ``AppFeature/SchedulerCoordinator`` that fires the daily brief and catches up on
/// wake/launch (design §11–§12).
///
/// The model is built by ``DaybriefApp`` (so the SwiftUI scenes can observe it as
/// `@State`) and handed here via ``attach(model:)`` before the app finishes
/// launching.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app model, injected by ``DaybriefApp`` at construction.
    private var model: AppModel?
    private var scheduler: SchedulerCoordinator?
    private static let logger = Logger(subsystem: "co.daybrief.app", category: "AppDelegate")

    /// Opens the main settings/onboarding window. Registered by ``DaybriefApp`` once the
    /// SwiftUI scene is available.
    var openMainWindow: (() -> Void)?

    /// Receives the app-owned model from ``DaybriefApp`` before launch completes.
    /// No-op if the environment failed to build (`model` is `nil`).
    func attach(model: AppModel?) {
        self.model = model
    }

    /// Handles the widget's `daybrief://` deep link. The widget is view-only, so a tap
    /// simply brings the app forward — the reader acts from the menu-bar panel. (The
    /// menu-bar popover can't be opened programmatically, so we don't force a window.)
    func application(_: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme?.lowercased() == "daybrief" }) else { return }
        NSApplication.shared.activate()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Register the bundled editorial serif (Tiempos Text) before any view
        // renders, so the brief panel draws in the real face from first paint.
        // Idempotent + run-once, and a no-op (graceful system-serif fallback) when
        // the git-ignored font files aren't present.
        DaybriefTheme.registerBundledFonts()

        // Menu-bar accessory: no Dock icon until the settings window opens.
        NSApplication.shared.setActivationPolicy(.accessory)

        guard let model else {
            // The environment failed to build; DaybriefApp shows the error state.
            Self.logger.error("No app model — environment failed to build at launch")
            return
        }

        // Start the scheduler (registers the wake observer, runs the launch
        // catch-up via `onWakeOrLaunch()`, and arms the next daily timer).
        let scheduler = SchedulerCoordinator(model: model)
        self.scheduler = scheduler

        Task { @MainActor in
            // Load persisted state + write default prompt files first so the
            // scheduler's catch-up sees the user's real brief time and config.
            await model.bootstrap()
            scheduler.start()
        }
    }

    func applicationWillTerminate(_: Notification) {
        scheduler?.stop()
    }

    /// Keep running in the menu bar when the last window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
