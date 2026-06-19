import AppFeature
import AppKit
import SwiftUI

/// The Daybrief app entry point: a menu-bar accessory whose `MenuBarExtra` hosts
/// the rich editorial brief panel, plus a standalone `Window` scene for
/// onboarding / settings (design §11).
///
/// The dependency graph (`AppEnvironment.live()`) is built once at launch and the
/// `AppModel` derived from it is held as app-owned `@State`. If the environment
/// fails to build (e.g. the database can't be opened), the app shows a calm error
/// state in the menu bar instead of crashing.
@main
struct DaybriefApp: App {
    /// The app delegate owns the activation policy and the long-lived scheduler.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.openWindow) private var openWindow

    /// The single app model, or `nil` if the environment failed to build.
    @State private var model: AppModel?
    /// A user-facing description of why the app couldn't start, if it didn't.
    @State private var launchError: String?

    init() {
        do {
            let environment = try AppEnvironment.live()
            let model = AppModel(environment: environment)
            _model = State(initialValue: model)
            // Hand the model to the delegate so it can bootstrap + drive the
            // scheduler from `applicationDidFinishLaunching`.
            appDelegate.attach(model: model)
        } catch {
            // Degrade gracefully: no model, a readable message, no crash.
            _launchError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        // The brief panel is no longer a `MenuBarExtra` scene: it's a custom status
        // item + floating panel owned by `AppDelegate` (`BriefPanelController`), so it
        // can pin to the screen's right edge with a real desktop gap below the menu
        // bar. The opener registered here gives that AppKit-side panel a reliable way
        // to open this SwiftUI window (a detached NSHostingView can't reach the
        // scene-connected `openWindow` itself).
        let _ = registerWindowOpener()

        // The setup / settings window. Opening it promotes the app to a regular
        // (Dock-visible, focusable) app; closing it drops back to accessory so the
        // app keeps living quietly in the menu bar.
        Window("Daybrief", id: Self.mainWindowID) {
            Group {
                if let model {
                    RootWindowView(model: model)
                } else {
                    LaunchErrorView(
                        message: launchError ?? "Daybrief couldn't start.",
                        openSettings: nil
                    )
                }
            }
            .onAppear {
                NSApplication.shared.setActivationPolicy(.regular)
                // Register the window opener for the widget's daybrief:// deep link.
                appDelegate.openMainWindow = { openWindow(id: Self.mainWindowID) }
            }
            .onDisappear { NSApplication.shared.setActivationPolicy(.accessory) }
        }
        .windowResizability(.contentSize)
        // The widget's daybrief:// deep link is handled in AppDelegate (it opens an
        // interactive brief window); this stops SwiftUI from also auto-surfacing the
        // settings window for that external event.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Daybrief Settings…") { openWindow(id: Self.mainWindowID) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// Captures the scene-connected `openWindow` action into the app delegate so the
    /// AppKit-owned brief panel (and the widget deep link) can open the settings
    /// window. Called as a side effect during `body` evaluation — which SwiftUI runs
    /// at launch — so the opener is live before the user can reach the panel's gear.
    @discardableResult
    private func registerWindowOpener() -> Bool {
        appDelegate.openMainWindow = { openWindow(id: Self.mainWindowID) }
        return true
    }

    /// The id of the standalone setup/settings window (shared with `AppFeature`).
    static let mainWindowID = DaybriefWindow.mainID
}

/// A calm fallback shown when the app environment failed to build, so a launch
/// failure never crashes or shows a blank menu (design §11 "honest about quiet
/// days" applied to errors too).
private struct LaunchErrorView: View {
    let message: String
    /// Opens the settings window, if available from this context.
    let openSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Daybrief couldn't start", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let openSettings {
                Button("Open Settings…", action: openSettings)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
    }
}
