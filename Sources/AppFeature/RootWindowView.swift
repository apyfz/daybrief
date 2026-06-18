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
        .background(DaybriefTheme.paper)
    }
}
