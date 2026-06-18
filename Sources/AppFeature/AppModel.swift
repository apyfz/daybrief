import ConnectorKit
import DaybriefCore
import Foundation
import LLMKit
import os
import Persistence
import Pipeline
import Secrets
import ServiceManagement
import SwiftUI

/// The single source of UI truth for Daybrief, owning all app state and the wiring
/// from SwiftUI into the pipeline, persistence, connectors, and Keychain.
///
/// This is the **only** `@MainActor`-isolated type in the codebase: every library
/// module is `nonisolated`, and the model hops to those actors/values with
/// `await`. State is exposed via `@Observable` so the brief panel, onboarding, and
/// settings views re-render on change. See `docs/build/appfeature-contract.md`.
@MainActor
@Observable
public final class AppModel {
    /// Where setup currently stands, which routes the window scene.
    public enum Setup: Sendable, Equatable {
        /// No usable AI key yet — the brief can't be synthesized.
        case needsAPIKey
        /// Key is set; the user is still walking through connect/spaces/time.
        case onboarding
        /// Setup is complete; the window shows Settings.
        case ready
    }

    /// The current setup phase.
    public private(set) var setup: Setup = .needsAPIKey
    /// The most recent brief, or `nil` if none has been generated.
    public private(set) var currentBrief: Brief?
    /// Whether a brief is currently being generated.
    public private(set) var isGenerating = false
    /// The most recent user-facing error, or `nil`.
    public private(set) var lastError: String?
    /// The configured connections (connectors + their accounts).
    public private(set) var connections: [Connection] = []
    /// The available spaces (Work / Personal / custom).
    public private(set) var spaces: [Space] = []

    /// The daily fire-time (bound by the time pickers).
    public var briefTime = FireTime(hour: 7, minute: 0)
    /// The selected LLM provider (bound by the provider pickers).
    public var selectedProvider: Provider = .openRouter
    /// The selected model id (bound by the model pickers).
    public var selectedModel = ""
    /// The live launch-at-login state (read from `SMAppService`).
    public var launchAtLogin = false

    private let environment: AppEnvironment
    private static let logger = Logger(subsystem: "co.daybrief.app", category: "AppModel")

    /// Creates the model over `environment`.
    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Bootstrap

    /// Loads persisted state into the model and writes the default prompt files.
    ///
    /// Reads spaces (seeding Work/Personal on first run), connections, the saved
    /// provider/model + brief time, the latest brief, and the live launch-at-login
    /// status, then computes the initial ``setup`` phase. Safe to call on launch.
    public func bootstrap() async {
        // Ensure the user-editable prompt files exist so Settings → Edit in Finder works.
        _ = try? PromptTemplate.writeDefaultsIfNeeded(to: environment.promptsDirectory)

        await seedDefaultSpacesIfNeeded()
        await reloadSpaces()
        await reloadConnections()
        await loadSettings()
        await loadLatestBrief()
        refreshLaunchAtLogin()

        recomputeSetup()
    }

    /// Re-derives the ``setup`` phase from current state.
    private func recomputeSetup() {
        if selectedModel.isEmpty {
            setup = .needsAPIKey
        } else if currentBrief == nil, connections.allSatisfy(\.accounts.isEmpty) {
            // Key set but nothing connected and nothing generated yet → keep onboarding.
            setup = setup == .ready ? .ready : .onboarding
        } else {
            setup = .ready
        }
    }

    // MARK: - API key + models

    /// Stores the API key for `provider` in the Keychain and remembers the selection.
    ///
    /// For keyless providers (Ollama) the key is ignored and only the base URL is
    /// persisted. Selecting a model afterwards (which proves the key works) is what
    /// advances setup past ``Setup/needsAPIKey``.
    public func saveAPIKey(_ key: String, provider: Provider, baseURL: URL?) async {
        lastError = nil
        selectedProvider = provider
        do {
            if provider.requiresAPIKey {
                try await environment.keychain.setString(key, for: Self.apiKeyRef(for: provider))
            }
            if let baseURL {
                try await environment.settings.setString(baseURL.absoluteString, forKey: Self.baseURLKey(for: provider))
            }
            try await environment.settings.set(provider.rawValue, for: SettingsStore.selectedProvider)
        } catch {
            lastError = "Could not save the API key."
            Self.logger.error("saveAPIKey failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lists the models the selected provider currently exposes.
    ///
    /// Builds the adapter from the stored key + base URL and asks the provider; on
    /// failure it surfaces a message and returns an empty list (the caller keeps the
    /// previous selection).
    public func availableModels() async -> [ModelInfo] {
        lastError = nil
        do {
            let config = try await providerConfig(model: selectedModel.isEmpty ? "placeholder" : selectedModel)
            let adapter = try environment.providerRegistry.makeAdapter(selectedProvider, config: config)
            return try await adapter.availableModels()
        } catch {
            lastError = "Could not load models — check your key and try again."
            Self.logger.error("availableModels failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Builds the ``LLMKit/ProviderConfig`` for the selected provider, resolving the
    /// key + base-URL override from the Keychain / settings.
    private func providerConfig(model: String) async throws -> ProviderConfig {
        let key: String?
        if selectedProvider.requiresAPIKey {
            key = try await environment.keychain.getString(for: Self.apiKeyRef(for: selectedProvider))
        } else {
            key = nil
        }
        let baseURLString = try await environment.settings.string(forKey: Self.baseURLKey(for: selectedProvider))
        let baseURL = baseURLString.flatMap(URL.init(string:))
        return ProviderConfig(apiKey: key, baseURL: baseURL, defaultModel: model)
    }

    // MARK: - Generation

    /// Generates today's brief now, working even with zero connectors (a quiet-day
    /// brief). Reflects progress in ``isGenerating`` and surfaces failures in
    /// ``lastError``. On success the new brief becomes ``currentBrief`` and setup
    /// advances to ``Setup/ready``.
    public func generateBriefNow() async {
        guard !isGenerating else { return }
        guard !selectedModel.isEmpty else {
            lastError = "Choose an AI model first."
            return
        }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        // Record the attempt up front — regardless of outcome — so a failure backs
        // off the wake/launch catch-up for the rest of the day instead of re-firing
        // (and re-spending on the LLM) on every wake. Success additionally stamps
        // `lastBriefDate` via the sink. Stamped as start-of-day to match the sink's
        // timezone-stable day key.
        await recordBriefAttempt()

        do {
            let config = try await providerConfig(model: selectedModel)
            let adapter = try environment.providerRegistry.makeAdapter(selectedProvider, config: config)
            let template = PromptTemplate.load(from: environment.promptsDirectory)

            var registry = environment.makeRegistry()
            let accountsByConnector = try await self.accountsByConnector()
            // Disable connectors with no enabled accounts so the fan-out skips them.
            for id in registry.registeredIDs where (accountsByConnector[id] ?? []).isEmpty {
                registry.setEnabled(false, for: id)
            }

            let sink = RepositoryBriefSink(
                repository: environment.briefRepository,
                settings: environment.settings
            )

            let brief = try await environment.generator.generate(
                registry: registry,
                accountsByConnector: accountsByConnector,
                tokenProvider: environment.tokenProvider,
                template: template,
                adapter: adapter,
                model: selectedModel,
                sink: sink
            )
            currentBrief = brief
            setup = .ready
        } catch is CancellationError {
            // Quiet — a cancelled generation isn't an error to surface.
        } catch let error as PipelineError {
            lastError = error.displayMessage
            Self.logger.error("generateBriefNow failed: \(error.displayMessage, privacy: .public)")
        } catch {
            lastError = "Could not write today's brief."
            Self.logger.error("generateBriefNow failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stamps `lastBriefAttemptDate` to today's start-of-day so the wake/launch
    /// catch-up backs off after a failed generation (see ``onWakeOrLaunch()``).
    ///
    /// Best-effort: a settings write failure here only weakens the back-off, so it
    /// is logged rather than surfaced — the generation itself still proceeds.
    private func recordBriefAttempt() async {
        let day = Calendar.current.startOfDay(for: Date())
        do {
            try await environment.settings.setDate(day, forKey: SettingsStore.lastBriefAttemptDateKey)
        } catch {
            Self.logger.error("recordBriefAttempt failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The enabled accounts for each connector, from the persisted connections.
    private func accountsByConnector() async throws -> [ConnectorID: [Account]] {
        var map: [ConnectorID: [Account]] = [:]
        for connection in connections where connection.isEnabled {
            map[connection.connectorId, default: []].append(contentsOf: connection.accounts)
        }
        return map
    }

    // MARK: - Connecting tools

    /// Runs the Google loopback OAuth flow for `id` (Calendar or Gmail) with the
    /// user's BYO Desktop client, persists the resulting token, and records the
    /// account under `space`.
    public func beginConnectGoogle(
        _ id: ConnectorID,
        clientID: String,
        clientSecret: String?,
        space: String
    ) async {
        lastError = nil
        let config = AppEnvironment.googleOAuthConfig(clientID: clientID, clientSecret: clientSecret)
        await connectGoogle(id, config: config, space: space)
    }

    /// Shared Google loopback-OAuth body for both the manual entry path
    /// (``beginConnectGoogle(_:clientID:clientSecret:space:)``) and the client-reuse
    /// path (``beginConnectGoogleReusingExistingClient(_:space:)``): runs the loopback
    /// flow with `config`, persists the resulting token + refresh parameters, and
    /// records the account under `space`.
    private func connectGoogle(_ id: ConnectorID, config: OAuthConfig, space: String) async {
        do {
            let presenter = WebAuthPresenter()
            let token = try await environment.oauthFlow.authorizeViaLoopback(
                config: config,
                presenter: presenter
            )

            let accountID = UUID()
            let tokenRef = AccountSecrets.tokenRef(for: accountID, connector: id)
            try await environment.keychain.setCodable(token, for: tokenRef)
            try await environment.keychain.setCodable(
                StoredOAuthClient(config: config),
                for: AccountSecrets.clientRef(for: tokenRef)
            )

            let account = Account(
                id: accountID,
                connectorId: id,
                label: Self.displayName(for: id),
                spaceKey: space,
                secretRef: tokenRef
            )
            try await upsertAccount(account, connectorId: id, connectionName: Self.displayName(for: id))
            await reloadConnections()
        } catch let error as ConnectorError {
            if case .userCancelled = error { return }
            lastError = error.displayMessage
            Self.logger.error("connectGoogle failed: \(error.displayMessage, privacy: .public)")
        } catch {
            lastError = "Could not connect Google."
            Self.logger.error("connectGoogle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether the user has already set up a Google Desktop OAuth client for one of
    /// the Google connectors (Calendar or Gmail), with its refresh parameters still
    /// resolvable from the Keychain.
    ///
    /// The onboarding Google screens use this to offer "Use the same Google client
    /// you already set up" once either connector is connected — Calendar and Gmail
    /// share a single Desktop client, so the second connector never needs the id /
    /// secret re-entered.
    public func hasExistingGoogleClient() async -> Bool {
        await existingGoogleOAuthConfig() != nil
    }

    /// Connects `id` (Calendar or Gmail) by **reusing** the Google Desktop OAuth
    /// client the user already set up for the other Google connector — no client id /
    /// secret re-entry.
    ///
    /// Loads the ``StoredOAuthClient`` from an existing Google account's derived
    /// client ref in the Keychain, then runs the same loopback flow as
    /// ``beginConnectGoogle(_:clientID:clientSecret:space:)``. If no existing client
    /// is found (the caller should have gated on ``hasExistingGoogleClient()``), it
    /// surfaces a message and does nothing — the caller falls back to manual entry.
    public func beginConnectGoogleReusingExistingClient(_ id: ConnectorID, space: String) async {
        lastError = nil
        guard let config = await existingGoogleOAuthConfig() else {
            lastError = "No existing Google client to reuse — enter your client ID and secret."
            return
        }
        await connectGoogle(id, config: config, space: space)
    }

    /// Loads the OAuth config from an already-connected Google account's stored client
    /// parameters, or `nil` if neither Calendar nor Gmail has a resolvable client.
    private func existingGoogleOAuthConfig() async -> OAuthConfig? {
        let googleAccounts = connections
            .filter { $0.connectorId == .gcal || $0.connectorId == .gmail }
            .flatMap(\.accounts)
        for account in googleAccounts {
            let tokenRef = AccountSecrets.tokenRef(for: account.id, connector: account.connectorId)
            let clientRef = AccountSecrets.clientRef(for: tokenRef)
            if let stored = try? await environment.keychain.getCodable(StoredOAuthClient.self, for: clientRef) {
                return stored.config
            }
        }
        return nil
    }

    /// Connects Slack from a pasted `xoxp-` user token, storing it in the Keychain
    /// and recording the account under `space`.
    ///
    /// Slack is treated as a **single-workspace** connector for v0: any previously
    /// connected Slack accounts (and their Keychain secrets) are removed first, so
    /// "Add or reconnect" *replaces* the existing workspace rather than appending a
    /// second one. (Google connectors keep their multi-account behavior.)
    public func connectSlack(userToken: String, workspaceLabel: String, space: String) async {
        lastError = nil
        do {
            // Single-workspace: clear any existing Slack accounts (token + client refs)
            // before adding the new one, so a reconnect never leaves a duplicate behind.
            let existingSlackAccounts = connections
                .filter { $0.connectorId == .slack }
                .flatMap(\.accounts)
            for account in existingSlackAccounts {
                await deleteAccountSecrets(accountID: account.id, connector: .slack)
            }
            if let slackConnection = connections.first(where: { $0.connectorId == .slack }) {
                try await environment.connectionRepository.deleteConnection(id: slackConnection.id)
            }

            let accountID = UUID()
            let tokenRef = AccountSecrets.tokenRef(for: accountID, connector: .slack)
            try await environment.keychain.setString(userToken, for: tokenRef)

            let account = Account(
                id: accountID,
                connectorId: .slack,
                label: workspaceLabel,
                spaceKey: space,
                secretRef: tokenRef
            )
            // Reload so `upsertAccount` sees the cleared state and creates a fresh
            // single-account Slack connection rather than reusing the stale in-memory one.
            await reloadConnections()
            try await upsertAccount(account, connectorId: .slack, connectionName: "Slack")
            await reloadConnections()
        } catch {
            lastError = "Could not connect Slack."
            Self.logger.error("connectSlack failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the connected account with `accountID`.
    ///
    /// Finds the owning connection and drops that account: if it was the connection's
    /// last account the whole connection is deleted, otherwise the connection is saved
    /// without it. The account's Keychain secrets (token ref + derived client ref) are
    /// deleted regardless. Best-effort and crash-free — any failure is surfaced in
    /// ``lastError`` and the connection list is reloaded.
    public func removeAccount(accountID: UUID) async {
        lastError = nil
        guard let connection = connections.first(where: { conn in
            conn.accounts.contains { $0.id == accountID }
        }) else { return }

        // The connector is needed to derive the Keychain refs; capture it before edits.
        let connector = connection.connectorId
        await deleteAccountSecrets(accountID: accountID, connector: connector)

        do {
            let remaining = connection.accounts.filter { $0.id != accountID }
            if remaining.isEmpty {
                try await environment.connectionRepository.deleteConnection(id: connection.id)
            } else {
                let updated = Connection(
                    id: connection.id,
                    connectorId: connection.connectorId,
                    displayName: connection.displayName,
                    accounts: remaining,
                    isEnabled: connection.isEnabled
                )
                try await environment.connectionRepository.save(updated)
            }
        } catch {
            lastError = "Could not remove the account."
            Self.logger.error("removeAccount failed: \(error.localizedDescription, privacy: .public)")
        }
        await reloadConnections()
    }

    /// Deletes the Keychain material for `accountID` under `connector`: the token ref
    /// and its derived OAuth client ref. Best-effort — a delete of a non-existent item
    /// is a no-op, and a failure is logged rather than surfaced (the DB row is still
    /// removed by the caller, so the account stops being used either way).
    private func deleteAccountSecrets(accountID: UUID, connector: ConnectorID) async {
        let tokenRef = AccountSecrets.tokenRef(for: accountID, connector: connector)
        let clientRef = AccountSecrets.clientRef(for: tokenRef)
        do {
            try await environment.keychain.delete(tokenRef)
            try await environment.keychain.delete(clientRef)
        } catch {
            Self.logger.error("deleteAccountSecrets failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-files the account with `accountID` under the space `spaceKey`.
    public func setSpace(accountID: UUID, to spaceKey: String) async {
        do {
            guard var connection = connections.first(where: { conn in
                conn.accounts.contains { $0.id == accountID }
            }) else { return }

            let accounts = connection.accounts.map { account -> Account in
                guard account.id == accountID else { return account }
                return Account(
                    id: account.id,
                    connectorId: account.connectorId,
                    label: account.label,
                    spaceKey: spaceKey,
                    secretRef: account.secretRef
                )
            }
            connection = Connection(
                id: connection.id,
                connectorId: connection.connectorId,
                displayName: connection.displayName,
                accounts: accounts,
                isEnabled: connection.isEnabled
            )
            try await environment.connectionRepository.save(connection)
            await reloadConnections()
        } catch {
            lastError = "Could not move the account to that space."
            Self.logger.error("setSpace failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds a new space with `displayName`, deriving a stable slug key from it.
    ///
    /// No-ops on an empty/whitespace name or when a space with the derived key (or the
    /// same display name) already exists, so the call is safe to wire straight to a
    /// text field's Add button. Reloads ``spaces`` on success.
    public func addSpace(displayName: String) async {
        lastError = nil
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = Self.spaceKey(from: trimmed)
        guard !key.isEmpty else { return }
        // Ignore duplicates by derived key or by display name.
        guard !spaces.contains(where: { $0.key == key || $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        do {
            try await environment.spaceRepository.save(Space(key: key, displayName: trimmed))
            await reloadSpaces()
        } catch {
            lastError = "Could not add the space."
            Self.logger.error("addSpace failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the space with `key`.
    ///
    /// Safeguards keep the model usable: it refuses to remove the **last** remaining
    /// space (an account must always have somewhere to live), and any accounts filed
    /// under the removed space are first re-filed under the first remaining space via
    /// the existing ``setSpace(accountID:to:)`` path. Reloads ``spaces`` and
    /// ``connections`` on success.
    public func removeSpace(key: String) async {
        lastError = nil
        // Never delete the last space.
        guard spaces.count > 1 else { return }
        guard spaces.contains(where: { $0.key == key }) else { return }
        // The fallback space accounts get reassigned to: the first space that isn't this one.
        guard let fallback = spaces.first(where: { $0.key != key }) else { return }

        // Reassign every account currently in this space to the fallback first, so no
        // account is orphaned pointing at a deleted space key.
        let orphanedAccountIDs = connections
            .flatMap(\.accounts)
            .filter { $0.spaceKey == key }
            .map(\.id)
        for accountID in orphanedAccountIDs {
            await setSpace(accountID: accountID, to: fallback.key)
        }

        do {
            try await environment.spaceRepository.delete(key: key)
            await reloadSpaces()
            await reloadConnections()
        } catch {
            lastError = "Could not remove the space."
            Self.logger.error("removeSpace failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Derives a stable, slug-like ``Space/key`` from a human display name:
    /// lowercased, non-alphanumeric runs collapsed to single hyphens, trimmed.
    static func spaceKey(from displayName: String) -> String {
        let lowered = displayName.lowercased()
        var slug = ""
        var lastWasHyphen = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                slug.append("-")
                lastWasHyphen = true
            }
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Adds `account` to its connector's connection (creating the connection on first
    /// account), persisting the result.
    private func upsertAccount(_ account: Account, connectorId: ConnectorID, connectionName: String) async throws {
        if var existing = connections.first(where: { $0.connectorId == connectorId }) {
            var accounts = existing.accounts.filter { $0.label != account.label }
            accounts.append(account)
            existing = Connection(
                id: existing.id,
                connectorId: connectorId,
                displayName: existing.displayName,
                accounts: accounts,
                isEnabled: existing.isEnabled
            )
            try await environment.connectionRepository.save(existing)
        } else {
            let connection = Connection(
                connectorId: connectorId,
                displayName: connectionName,
                accounts: [account],
                isEnabled: true
            )
            try await environment.connectionRepository.save(connection)
        }
    }

    // MARK: - Schedule + launch

    /// Persists the daily brief fire-time.
    public func setBriefTime(_ time: FireTime) async {
        briefTime = time
        do {
            try await environment.settings.set(time.encoded, for: SettingsStore.briefTime)
        } catch {
            Self.logger.error("setBriefTime failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Toggles launch-at-login via `SMAppService`, then re-reads the live status.
    public func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("setLaunchAtLogin failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLaunchAtLogin()
        Task { try? await environment.settings.set(on, for: SettingsStore.launchAtLogin) }
    }

    /// Re-reads the live `SMAppService` status into ``launchAtLogin``.
    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Reveals the user-editable prompt/template directory in Finder.
    public func openPromptTemplateInFinder() {
        _ = try? PromptTemplate.writeDefaultsIfNeeded(to: environment.promptsDirectory)
        NSWorkspace.shared.activateFileViewerSelecting([environment.promptsDirectory])
    }

    /// The scheduler catch-up entry point: generate today's brief if the fire-time
    /// has passed and we haven't already generated — *or attempted* — one today.
    /// Called on launch and on wake.
    ///
    /// The attempt guard (not just the success guard) is what stops a failed brief
    /// from re-firing — and re-spending on the LLM — on every subsequent wake all
    /// day: a failed run still records `lastBriefAttemptDate`, so this catch-up
    /// backs off until tomorrow. The manual ``generateBriefNow()`` path does not
    /// route through here, so the user can always retry by hand.
    public func onWakeOrLaunch() async {
        // Don't auto-generate until setup is complete: a fresh launch with no
        // configured model must land in onboarding, not "fail" into an error state.
        guard setup == .ready else { return }
        let scheduler = BriefScheduler(fireTime: briefTime)
        let lastSuccess = (try? await environment.settings.date(forKey: SettingsStore.lastBriefDateKey)) ?? nil
        let lastAttempt = (try? await environment.settings.date(forKey: SettingsStore.lastBriefAttemptDateKey)) ?? nil
        if scheduler.shouldGenerateOnCatchUp(
            now: Date(),
            lastSuccessDate: lastSuccess,
            lastAttemptDate: lastAttempt
        ) {
            await generateBriefNow()
        }
    }

    // MARK: - Loading

    private func seedDefaultSpacesIfNeeded() async {
        do {
            let existing = try await environment.spaceRepository.all()
            guard existing.isEmpty else { return }
            try await environment.spaceRepository.save(Space(key: "work", displayName: "Work"))
            try await environment.spaceRepository.save(Space(key: "personal", displayName: "Personal"))
        } catch {
            Self.logger.error("seedDefaultSpaces failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reloadSpaces() async {
        spaces = (try? await environment.spaceRepository.all()) ?? spaces
    }

    private func reloadConnections() async {
        connections = (try? await environment.connectionRepository.all()) ?? connections
    }

    private func loadSettings() async {
        if let providerRaw = try? await environment.settings.get(SettingsStore.selectedProvider) ?? nil,
           let provider = Provider(rawValue: providerRaw)
        {
            selectedProvider = provider
        }
        if let model = try? await environment.settings.get(SettingsStore.selectedModel) ?? nil {
            selectedModel = model
        }
        if let timeRaw = try? await environment.settings.get(SettingsStore.briefTime) ?? nil,
           let time = FireTime(timeRaw)
        {
            briefTime = time
        }
    }

    private func loadLatestBrief() async {
        currentBrief = (try? await environment.briefRepository.loadLatest()) ?? currentBrief
    }

    /// Persists `selectedModel` whenever the user picks a model. Call after binding.
    public func persistSelectedModel() async {
        try? await environment.settings.set(selectedModel, for: SettingsStore.selectedModel)
    }

    // MARK: - Secret coordinates

    /// The ``DaybriefCore/SecretRef`` for `provider`'s API key.
    static func apiKeyRef(for provider: Provider) -> SecretRef {
        SecretRef(service: "co.daybrief.llm-key", account: provider.rawValue)
    }

    /// The settings key for `provider`'s base-URL override.
    static func baseURLKey(for provider: Provider) -> String {
        "llm_base_url_\(provider.rawValue)"
    }

    /// A human-facing default account label for a freshly connected connector.
    static func displayName(for id: ConnectorID) -> String {
        switch id {
        case .gcal: "Google Calendar"
        case .gmail: "Gmail"
        case .slack: "Slack"
        default: id.rawValue.capitalized
        }
    }

    // MARK: - Preview support

    /// Seeds the model's display state directly, bypassing ``bootstrap()``.
    ///
    /// Used only by ``preview(brief:)`` to populate a `BriefPanelView` for SwiftUI
    /// previews and offscreen snapshots without any asynchronous loading. It writes
    /// the two `private(set)` display fields and does not change runtime behavior on
    /// the live path.
    func applyPreviewState(brief: Brief?, setup: Setup) {
        currentBrief = brief
        self.setup = setup
    }

    /// Reloads ``spaces`` and ``connections`` from the repositories without touching
    /// `SMAppService`, the prompt files, or the setup phase.
    ///
    /// Test-only seam: lets a test seed the in-memory repositories directly and then
    /// pull that state into the model, exercising the space/account management paths
    /// without the side effects of ``bootstrap()``.
    func loadForTesting() async {
        await reloadSpaces()
        await reloadConnections()
    }
}
