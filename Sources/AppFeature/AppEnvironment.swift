import ConnectorKit
import DaybriefCore
import Foundation
import GmailConnector
import GoogleCalendarConnector
import LLMKit
import NotionConnector
import Persistence
import Pipeline
import Secrets
import SlackConnector

/// The dependency graph for ``AppModel``: the database, Keychain, repositories,
/// connector registry, LLM provider registry, OAuth flow, and the brief pipeline,
/// constructed once at launch and injected into the model.
///
/// `live()` builds the real graph (on-disk DB, real Keychain, real network
/// transports, all three connectors registered). Tests can build the same struct
/// with in-memory / stub collaborators.
public struct AppEnvironment: Sendable {
    /// The Keychain store for tokens + API keys.
    public let keychain: KeychainStore
    /// The brief repository (persisted briefs + their source items).
    public let briefRepository: BriefRepository
    /// The connection repository (configured connectors + their accounts).
    public let connectionRepository: ConnectionRepository
    /// The space repository (Work / Personal / custom).
    public let spaceRepository: SpaceRepository
    /// Small scalar settings (brief time, provider/model, last-brief day).
    public let settings: SettingsStore
    /// The LLM provider/model registry.
    public let providerRegistry: ProviderRegistry
    /// The OAuth flow used to mint + refresh Google tokens.
    public let oauthFlow: OAuthFlow
    /// The brief pipeline orchestrator.
    public let generator: BriefGenerator
    /// The token provider connectors use during a fetch.
    public let tokenProvider: any TokenProvider
    /// The directory the user-editable prompt/template files live in.
    public let promptsDirectory: URL

    /// Creates an environment from explicit collaborators (used by `live()` and tests).
    public init(
        keychain: KeychainStore,
        briefRepository: BriefRepository,
        connectionRepository: ConnectionRepository,
        spaceRepository: SpaceRepository,
        settings: SettingsStore,
        providerRegistry: ProviderRegistry,
        oauthFlow: OAuthFlow,
        generator: BriefGenerator,
        tokenProvider: any TokenProvider,
        promptsDirectory: URL
    ) {
        self.keychain = keychain
        self.briefRepository = briefRepository
        self.connectionRepository = connectionRepository
        self.spaceRepository = spaceRepository
        self.settings = settings
        self.providerRegistry = providerRegistry
        self.oauthFlow = oauthFlow
        self.generator = generator
        self.tokenProvider = tokenProvider
        self.promptsDirectory = promptsDirectory
    }

    /// Builds the live production dependency graph.
    ///
    /// Opens the on-disk database under Application Support (unencrypted by default —
    /// the SQLCipher key path is a documented build task), wires the real Keychain,
    /// network transports, and all three connectors.
    ///
    /// - Throws: a filesystem / `Persistence` error if the database can't be opened.
    public static func live() throws -> AppEnvironment {
        let keychain = KeychainStore()

        let dbURL = applicationSupportDirectory()
            .appendingPathComponent("daybrief.sqlite")
        // TODO(SQLCipher): pass `encryptionKey: try keychain.databaseKey()` once the
        // SQLCipher-enabled GRDB build is wired (see docs/build/grdb-sqlcipher.md).
        // The default SPM build ships plain GRDB, so we open unencrypted to stay green.
        let database = try DatabaseManager(url: dbURL)

        let queue = database.queue
        let briefRepository = BriefRepository(queue: queue)
        let connectionRepository = ConnectionRepository(queue: queue)
        let spaceRepository = SpaceRepository(queue: queue)
        let settings = SettingsStore(queue: queue)

        let attribution = OpenRouterAttribution(
            referer: "https://daybrief.co",
            title: "Daybrief"
        )
        let providerRegistry = ProviderRegistry(attribution: attribution)
        let oauthFlow = OAuthFlow(transport: URLSessionHTTPTransport())
        let generator = BriefGenerator()
        let tokenProvider = KeychainTokenProvider(keychain: keychain)

        let promptsDirectory = PromptTemplate.defaultDirectory()

        return AppEnvironment(
            keychain: keychain,
            briefRepository: briefRepository,
            connectionRepository: connectionRepository,
            spaceRepository: spaceRepository,
            settings: settings,
            providerRegistry: providerRegistry,
            oauthFlow: oauthFlow,
            generator: generator,
            tokenProvider: tokenProvider,
            promptsDirectory: promptsDirectory
        )
    }

    // MARK: - Connector registry

    /// Builds a connector registry with every connector registered against
    /// `tokenProvider`. Enabled flags are applied by the caller from the persisted
    /// connections.
    public func makeRegistry() -> ConnectorRegistry {
        ConnectorRegistry([
            GoogleCalendarConnector(tokenProvider: tokenProvider),
            GmailConnector(tokenProvider: tokenProvider),
            SlackConnector(tokenProvider: tokenProvider),
            NotionConnector(tokenProvider: tokenProvider),
        ])
    }

    /// The Application Support directory for Daybrief, created if necessary.
    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Daybrief", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Google OAuth config

extension AppEnvironment {
    /// The Google OAuth scopes Daybrief requests for the combined Calendar + Gmail
    /// Desktop client (read-only on both). One consent covers both connectors.
    static let googleScopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/gmail.readonly",
    ]

    /// Builds the ``ConnectorKit/OAuthConfig`` for a user's BYO Google Desktop client.
    static func googleOAuthConfig(clientID: String, clientSecret: String?) -> OAuthConfig {
        OAuthConfig(
            authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: googleScopes,
            usesPKCE: true
        )
    }
}
