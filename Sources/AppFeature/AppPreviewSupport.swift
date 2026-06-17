import ConnectorKit
import DaybriefCore
import Foundation
import LLMKit
import Persistence
import Pipeline
import Secrets

// Preview / snapshot affordances.
//
// These build an `AppModel` over an entirely in-memory, no-op dependency graph so a
// `BriefPanelView` can be rendered offscreen (SwiftUI previews, `ImageRenderer`
// snapshots) without a live database, real Keychain access, or any network. They
// touch no production code paths: `AppEnvironment.preview()` mirrors the collaborator
// set of `live()` but with an in-memory `DatabaseManager`, an empty `ProviderRegistry`,
// and a prompts directory under the system temp dir. Nothing here is wired into the
// app's launch path.

public extension AppEnvironment {
    /// Builds an in-memory, no-op dependency graph for previews and offscreen snapshots.
    ///
    /// Everything is local: an in-memory `DatabaseManager`, a `KeychainStore` that is
    /// never read at render time, an empty `ProviderRegistry`, and a prompts directory
    /// under the system temp dir. No network or real-keychain access happens when a
    /// view is merely rendered, since rendering reads model state directly rather than
    /// generating a brief.
    ///
    /// - Throws: a `Persistence` error if the in-memory database can't be opened
    ///   (not expected in practice).
    static func preview() throws -> AppEnvironment {
        let database = try DatabaseManager.inMemory()
        let queue = database.queue

        let keychain = KeychainStore()
        return AppEnvironment(
            keychain: keychain,
            briefRepository: BriefRepository(queue: queue),
            connectionRepository: ConnectionRepository(queue: queue),
            spaceRepository: SpaceRepository(queue: queue),
            settings: SettingsStore(queue: queue),
            providerRegistry: ProviderRegistry(),
            oauthFlow: OAuthFlow(transport: URLSessionHTTPTransport()),
            generator: BriefGenerator(),
            tokenProvider: KeychainTokenProvider(keychain: keychain),
            promptsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("daybrief-preview-prompts", isDirectory: true)
        )
    }
}

public extension AppModel {
    /// Builds an `AppModel` over ``AppEnvironment/preview()`` showing `brief`, with
    /// ``AppModel/setup`` forced to ``AppModel/Setup/ready``.
    ///
    /// Intended only for previews and offscreen snapshots — it bypasses ``bootstrap()``
    /// and seeds the model's display state directly via an internal preview setter, so
    /// no asynchronous loading or network access is involved.
    @MainActor
    static func preview(brief: Brief) -> AppModel {
        // The in-memory environment can only fail to build if an in-memory SQLite
        // database can't be opened, which does not happen in practice. A preview-only
        // path is the one place a `try!` is justified (per CONVENTIONS: provably-safe).
        let environment = try! AppEnvironment.preview()
        let model = AppModel(environment: environment)
        model.applyPreviewState(brief: brief, setup: .ready)
        return model
    }
}
