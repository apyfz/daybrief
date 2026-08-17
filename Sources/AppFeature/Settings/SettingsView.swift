import DaybriefCore
import LLMKit
import Pipeline
import SlackConnector
import SwiftUI

/// The settings screen shown once setup is complete: review/retune everything from
/// onboarding without re-running the flow.
///
/// Sections: connected tools, the Slack channel selection,
/// the provider + model picker, the daily brief time, the launch-at-login toggle
/// (driven by `SMAppService` live status through `model.setLaunchAtLogin`), and a
/// button to open the user-editable prompt/template files in Finder.
/// The Tools pane: a list of every connector that pushes into that connector's own
/// setup, in place.
///
/// Selecting a tool used to throw up a fixed 560×640 modal with its own back bar and
/// footer — a separate world for the one task that most needs to feel part of the app.
/// The detail now lives in this pane, so setting up a tool is somewhere you go rather
/// than something that interrupts you.
struct ToolsPane: View {
    @Bindable var model: AppModel
    @State private var selected: OnboardingConnector?

    var body: some View {
        if let selected {
            ConnectorDetail(model: model, connector: selected) { self.selected = nil }
        } else {
            connectorList
        }
    }

    private var connectorList: some View {
        SettingsGroup {
            ForEach(Array(OnboardingConnector.allCases.enumerated()), id: \.element.id) { index, connector in
                if index > 0 { SettingsRowDivider() }
                ConnectorRow(
                    model: model,
                    connector: connector,
                    action: { selected = connector }
                )
            }
        }
    }
}

/// One connector in the Tools list: mark, name, what it's reading, and a chevron.
///
/// Deliberately one row per tool. The previous screen spent two — a connector row and
/// a repeated account row underneath — and put a loud "Add or reconnect" pill on every
/// one, so the page read as a wall of buttons rather than a list of what's connected.
private struct ConnectorRow: View {
    @Bindable var model: AppModel
    let connector: OnboardingConnector
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DaybriefIcon.connector(connector.connectorID)
                    .daybriefIcon(size: 15)
                    .foregroundStyle(DaybriefTheme.ink)
                    .frame(width: 28, height: 28)
                    .background(DaybriefTheme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(connector.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DaybriefTheme.ink)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }

                Spacer(minLength: 12)

                if !isConnected {
                    Text("Set up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DaybriefTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DaybriefTheme.accent.opacity(0.35), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DaybriefTheme.ink.opacity(isHovering ? 0.04 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var accounts: [Account] {
        model.connections.first { $0.connectorId == connector.connectorID }?.accounts ?? []
    }

    private var isConnected: Bool { !accounts.isEmpty }

    /// What this tool is currently contributing, in the row itself — the account it
    /// reads, and for Slack how many channels are covered.
    private var status: String {
        guard let first = accounts.first else { return connector.surfaces }
        var parts = [first.label]
        if accounts.count > 1 { parts.append("+\(accounts.count - 1) more") }
        if connector.connectorID == .slack {
            let count = model.selectedSlackChannelIDs.count
            parts.append(count == 1 ? "1 channel" : "\(count) channels")
        }
        return parts.joined(separator: " · ")
    }
}

/// A connector's setup and accounts, shown inside the Tools pane.
private struct ConnectorDetail: View {
    @Bindable var model: AppModel
    let connector: OnboardingConnector
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("All tools")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityLabel("Back to all tools")

            if let connection = model.connections.first(where: { $0.connectorId == connector.connectorID }),
               !connection.accounts.isEmpty {
                SettingsGroup(title: "Accounts") {
                    ForEach(Array(connection.accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 { SettingsRowDivider() }
                        ConnectionRow(model: model, connection: connection, account: account)
                    }
                }
            }

            if connector.connectorID == .slack,
               model.connections.contains(where: { $0.connectorId == .slack && !$0.accounts.isEmpty }) {
                SettingsGroup(title: "Channels") {
                    SlackChannelsSection(model: model)
                }
            }

            ConnectorDetailScreen(model: model, connector: connector, onClose: onBack)
                .environment(\.connectorChrome, .inline)
        }
    }
}

/// The Brief pane: when the edition fires, and the prompt/template that gives it voice.
struct BriefPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "Delivery") {
                BriefScheduleSection(model: model)
            }
            SettingsGroup(title: "Voice") {
                BriefVoiceSection(model: model)
            }
        }
    }
}

/// The Model pane: provider, key, and model selection.
struct ModelPane: View {
    @Bindable var model: AppModel

    var body: some View {
        ModelSection(model: model)
    }
}

/// The App pane: how Daybrief behaves on the machine.
struct AppPane: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsGroup {
            AppSection(model: model)
        }
    }
}

// MARK: - Connections

/// Shows every connector (Calendar / Gmail / Slack) with its status and a Set up /
/// Add button that opens the dedicated setup screen — so tools skipped during
/// onboarding can be added later — plus a per-account Space picker for connected ones.
private struct ConnectionsSection: View {
    @Bindable var model: AppModel
    @State private var sheet: OnboardingConnector?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(OnboardingConnector.allCases) { connector in
                if connector != OnboardingConnector.allCases.first {
                    Divider().overlay(DaybriefTheme.ink.opacity(0.06))
                }
                connectorBlock(connector)
            }
        }
        .sheet(item: $sheet) { connector in
            ConnectorDetailScreen(model: model, connector: connector, onClose: { sheet = nil })
        }
    }

    @ViewBuilder
    private func connectorBlock(_ connector: OnboardingConnector) -> some View {
        let connection = model.connections.first { $0.connectorId == connector.connectorID }
        let accounts = connection?.accounts ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                connector.icon
                    .daybriefIcon(size: 15)
                    .foregroundStyle(DaybriefTheme.ink)
                    .frame(width: 28, height: 28)
                    .background(DaybriefTheme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(connector.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DaybriefTheme.ink)
                    Text(accounts.isEmpty ? "Not connected" : "Connected")
                        .font(.system(size: 11))
                        .foregroundStyle(accounts.isEmpty ? DaybriefTheme.inkSecondary : DaybriefTheme.ink.opacity(0.7))
                }
                Spacer(minLength: 12)

                DBSecondaryButton(
                    accounts.isEmpty ? "Set up" : "Add or reconnect",
                    systemImage: accounts.isEmpty ? "plus" : "arrow.clockwise"
                ) {
                    sheet = connector
                }
            }

            // Per-account Space pickers for whatever's connected under this connector.
            if let connection {
                ForEach(accounts) { account in
                    ConnectionRow(model: model, connection: connection, account: account)
                        .padding(.leading, 40)
                }
            }
        }
    }
}

/// One account row: icon, label, connection name, and a destructive Remove button
/// (confirmation-gated).
private struct ConnectionRow: View {
    @Bindable var model: AppModel
    let connection: Connection
    let account: Account

    @State private var confirmingRemove = false

    var body: some View {
        HStack(spacing: 12) {
            DaybriefIcon.connector(connection.connectorId)
                .daybriefIcon(size: 15)
                .foregroundStyle(DaybriefTheme.ink)
                .frame(width: 28, height: 28)
                .background(DaybriefTheme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(account.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.ink)
                Text(connection.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            Spacer(minLength: 12)

            Button {
                confirmingRemove = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Remove this account")
            .confirmationDialog(
                "Remove \(account.label)?",
                isPresented: $confirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task { await model.removeAccount(accountID: account.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This disconnects the account and deletes its saved credentials. You can reconnect it later.")
            }
        }
    }

}

// MARK: - Slack channels

/// The Slack channel selection, rendered by the shared ``SlackChannelPicker`` so
/// Settings and onboarding always describe the same capped, opt-in rule.
private struct SlackChannelsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SlackChannelPicker(
            model: model,
            caption: "Pick the channels worth reading in your brief. Direct messages and "
                + "@-mentions are always included."
        )
    }
}

// MARK: - Model

/// Provider + API key + model picker. Lets you (re-)enter the AI key and load models
/// without re-running onboarding.
private struct ModelSection: View {
    @Bindable var model: AppModel

    @State private var models: [ModelInfo] = []
    @State private var apiKey = ""
    @State private var isLoading = false
    @State private var savedNote: String?
    @State private var showAllModels = false

    /// The curated, reliable models (the picker leads with these).
    private var recommendedModels: [ModelInfo] { models.filter(\.isRecommended) }
    /// Everything else from the (already dead-entry-filtered) catalogue.
    private var otherModels: [ModelInfo] { models.filter { !$0.isRecommended } }

    /// What the picker actually lists. Default: just the recommended models (a short,
    /// reliable set) plus the current selection if it isn't one. "Show all" reveals the
    /// full catalogue. A single flat list — macOS `Picker` flattens `Section`s, so we
    /// control membership directly rather than relying on sectioning to hide rows.
    private var visibleModels: [ModelInfo] {
        models.recommendedFirst(selection: model.selectedModel, showAll: showAllModels)
    }

    /// One picker row, flagging free models so the cost/availability tradeoff is visible.
    @ViewBuilder
    private func modelRow(_ info: ModelInfo) -> some View {
        Text((info.displayName ?? info.id) + (info.isFree ? " · free" : "")).tag(info.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledRow(label: "Provider") {
                Picker("Provider", selection: $model.selectedProvider) {
                    ForEach(Provider.allCases) { provider in
                        Text(displayName(provider)).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            if model.selectedProvider.requiresAPIKey {
                LabeledRow(label: "API key") {
                    SecureField("Paste a new key (blank keeps current)", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
            }

            LabeledRow(label: "Model") {
                HStack(spacing: 8) {
                    if models.isEmpty {
                        Text(model.selectedModel.isEmpty ? "Save & load to choose" : model.selectedModel)
                            .font(.system(size: 13))
                            .foregroundStyle(DaybriefTheme.inkSecondary)
                            .lineLimit(1)
                    } else {
                        Picker("Model", selection: $model.selectedModel) {
                            ForEach(visibleModels) { modelRow($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        .onChange(of: model.selectedModel) { _, _ in
                            Task { await model.persistSelectedModel() }
                        }
                    }
                    DBSecondaryButton(isLoading ? "Loading…" : "Save & load", systemImage: "arrow.clockwise") {
                        Task { await saveAndLoad() }
                    }
                    .disabled(isLoading)
                }
            }

            if !recommendedModels.isEmpty, !otherModels.isEmpty {
                Toggle("Show all models", isOn: $showAllModels)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }

            if let selected = models.first(where: { $0.id == model.selectedModel }), selected.isFree {
                Text("Free models can be rate-limited and may need prompt logging enabled in your OpenRouter privacy settings (openrouter.ai/settings/privacy).")
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let savedNote {
                Text(savedNote)
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Saves a freshly-pasted key (if any), then loads the provider's models. Clears
    /// the field after saving so the key isn't left on screen.
    private func saveAndLoad() async {
        isLoading = true
        defer { isLoading = false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            await model.saveAPIKey(key, provider: model.selectedProvider, baseURL: nil)
            apiKey = ""
            savedNote = model.lastError == nil ? "Key saved to your Keychain." : nil
        }
        models = await model.availableModels()
        // Seed a fresh setup with a known-good recommended model (not just whatever
        // sorts first), falling back to the first available only if none are recommended.
        if model.selectedModel.isEmpty, let preferred = models.first(where: \.isRecommended) ?? models.first {
            model.selectedModel = preferred.id
            await model.persistSelectedModel()
        }
    }

    private func displayName(_ provider: Provider) -> String {
        switch provider {
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .ollama: "Ollama (local)"
        }
    }
}

// MARK: - Schedule

/// The daily brief-time picker.
private struct BriefScheduleSection: View {
    @Bindable var model: AppModel

    var body: some View {
        LabeledRow(label: "Brief time") {
            // A single editable time control (the static duplicate display was removed).
            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
                .labelsHidden()
                .font(.system(size: 14, weight: .semibold))
        }
    }

    private var timeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(
                    bySettingHour: model.briefTime.hour,
                    minute: model.briefTime.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let time = FireTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
                model.briefTime = time
                Task { await model.setBriefTime(time) }
            }
        )
    }
}

// MARK: - Voice

/// The prompt + render template that give the edition its voice, opened in Finder.
/// Lives with the brief rather than under App: it changes what the edition reads like,
/// not how the app behaves.
private struct BriefVoiceSection: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prompt & template")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.ink)
                Text("Edit the synthesis prompt and render template to retune the brief's voice and layout.")
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            DBSecondaryButton("Edit in Finder", systemImage: "square.and.pencil") {
                model.openPromptTemplateInFinder()
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - App

/// Launch-at-login toggle and the prompt/template editor button.
private struct AppSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: launchBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DaybriefTheme.ink)
                    Text("Daybrief stays in your menu bar so it's ready each morning.")
                        .font(.system(size: 11))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(DaybriefTheme.accent)
        }
    }

    /// Bridges the toggle to `model.launchAtLogin` (read) / `setLaunchAtLogin` (write),
    /// so the displayed state always reflects the live `SMAppService` status.
    private var launchBinding: Binding<Bool> {
        Binding<Bool>(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}

/// A label + trailing control row used throughout settings.
private struct LabeledRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DaybriefTheme.ink)
            Spacer(minLength: 16)
            control
        }
    }
}
