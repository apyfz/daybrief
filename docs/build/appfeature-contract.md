# AppFeature — shared contract (W3)

All `AppFeature` agents build against these exact shapes. `AppFeature` is the ONLY `@MainActor`-isolated target. It imports DaybriefCore, Pipeline, Persistence, Secrets, LLMKit, BriefRender, ConnectorKit, and the three connector targets (to wire them). Read the design doc + `docs/design/brief-design-language.md` (+ the reference image `docs/design/reference-dia-morning-brief.png`) for the panel.

## State + wiring

```swift
import SwiftUI
import Observation

@MainActor @Observable
public final class AppModel {
    public enum Setup: Sendable, Equatable { case needsAPIKey, onboarding, ready }
    public private(set) var setup: Setup
    public private(set) var currentBrief: Brief?
    public private(set) var isGenerating: Bool
    public private(set) var lastError: String?
    public private(set) var connections: [Connection]
    public private(set) var spaces: [Space]
    public var briefTime: FireTime                 // from Pipeline
    public var selectedProvider: LLMKit.Provider
    public var selectedModel: String
    public var launchAtLogin: Bool

    public init(environment: AppEnvironment)
    public func bootstrap() async                  // load persisted state; write default prompt files
    public func saveAPIKey(_ key: String, provider: LLMKit.Provider, baseURL: URL?) async
    public func availableModels() async -> [ModelInfo]
    public func generateBriefNow() async           // works with ZERO connectors → "quiet day" brief
    public func beginConnectGoogle(_ id: ConnectorID, clientID: String, clientSecret: String?, space: String) async
    public func connectSlack(userToken: String, workspaceLabel: String, space: String) async
    public func setSpace(accountID: UUID, to spaceKey: String) async
    public func setBriefTime(_ time: FireTime) async
    public func setLaunchAtLogin(_ on: Bool)
    public func openPromptTemplateInFinder()
    public func onWakeOrLaunch() async             // scheduler catch-up entry point
}

// Bundles all dependencies; `live()` builds the real graph (DB, Keychain, registries, connectors).
public struct AppEnvironment: Sendable {
    public static func live() throws -> AppEnvironment
}

// ASWebAuthenticationSession-backed, conforms ConnectorKit.AuthPresenter.
@MainActor public final class WebAuthPresenter: AuthPresenter { public init() }

// Keychain + OAuthFlow refresh (Google) / stored xoxp passthrough (Slack).
public struct KeychainTokenProvider: TokenProvider { public init(keychain: KeychainStore) }

// DispatchSourceTimer + NSWorkspace wake observer; wraps generation in beginActivity(.userInitiated).
@MainActor public final class SchedulerCoordinator { public init(model: AppModel); public func start() }
```

## Views (each takes the model)

```swift
public struct BriefPanelView: View { public init(model: AppModel) }   // the editorial periodical (showpiece)
public struct OnboardingView: View { public init(model: AppModel) }   // API key → connect tools → spaces → brief time
public struct SettingsView: View   { public init(model: AppModel) }   // connections, model, brief time, launch-at-login, prompt file
public struct RootWindowView: View { public init(model: AppModel) }   // routes onboarding vs settings for the Window scene
```

## Design system (`DaybriefTheme`)
```swift
public enum DaybriefTheme {
    public static let paper: Color        // warm cream ~#FAF7F0
    public static let ink: Color          // muted warm near-black
    public static let inkSecondary: Color // muted gray
    public static let accent: Color       // golden yellow ~#F2C200
    public static func serifDisplay(_ size: CGFloat) -> Font  // .system(size:design:.serif) weight tuned
    public static func serifBody(_ size: CGFloat) -> Font
}
public struct ActionBadge: View { public init(label: String) }          // the starburst "Let's do it →" badge
extension View { public func editorialCard() -> some View }              // soft rounded card + gentle shadow
public struct HeroArtworkView: View { public init(_ hero: HeroArtwork?) } // bundled image OR graceful warm placeholder
```

## App target (Xcode, thin) uses
- `MenuBarExtra("Daybrief", systemImage: "sun.max") { BriefPanelView(model: model) }.menuBarExtraStyle(.window)`
- `Window("Daybrief", id: "daybrief-main") { RootWindowView(model: model) }`
- `NSApplicationDelegateAdaptor` → `setActivationPolicy(.accessory)`, start `SchedulerCoordinator`, register wake → `model.onWakeOrLaunch()`. Info.plist `LSUIElement = true` (no Dock icon; promote to `.regular` when opening the window, demote on close).
