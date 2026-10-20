import AppKit
import SwiftUI

/// The root of the standalone window scene (design §11): the menu-bar popover
/// hosts the brief, while this window hosts setup and settings.
///
/// Routes to ``OnboardingView`` until setup reaches `.ready` (i.e. while
/// `model.setup` is `.needsAPIKey` or `.onboarding`), then to ``SettingsView``.
public struct RootWindowView: View {
    private let model: AppModel

    /// Creates the root window bound to `model`.
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.setup == .ready {
                SettingsView(model: model)
            } else {
                OnboardingView(model: model)
            }
        }
        .background(SettingsWindowMaterial().ignoresSafeArea())
    }
}

/// Behind-window material lets the desktop show through the settings canvas.
struct SettingsWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowMaterialView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private final class WindowMaterialView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.styleMask.insert(.fullSizeContentView)
            window?.isOpaque = false
            window?.backgroundColor = .clear
            window?.titlebarAppearsTransparent = true
        }
    }
}

/// Fit each settings pane once when selected, preserving the window's top edge.
/// Field edits and ordinary user resizing do not repeatedly reset the frame.
struct SettingsWindowSizing: NSViewRepresentable {
    let pane: SettingsPane

    func makeNSView(context: Context) -> SizingView {
        let view = SizingView()
        view.pane = pane
        return view
    }

    func updateNSView(_ view: SizingView, context: Context) {
        view.pane = pane
        view.fitPane()
    }

    final class SizingView: NSView {
        var pane: SettingsPane = .tools
        private var fittedPane: SettingsPane?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fitPane()
        }

        func fitPane() {
            guard let window, fittedPane != pane else { return }
            fittedPane = pane
            let selectedPane = pane
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pane == selectedPane else { return }
                let height: CGFloat = switch selectedPane {
                case .tools: 500
                case .model: 460
                case .brief: 480
                case .app: 400
                }
                let top = window.frame.maxY
                window.setContentSize(NSSize(width: 780, height: height))
                window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            }
        }
    }
}
