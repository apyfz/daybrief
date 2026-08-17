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
public struct SettingsView: View {
    @Bindable private var model: AppModel

    /// Creates the settings screen bound to `model`.
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                SettingsSection(title: "Connected tools", systemImage: "link") {
                    ConnectionsSection(model: model)
                }

                if model.connections.contains(where: { $0.connectorId == .slack && !$0.accounts.isEmpty }) {
                    SettingsSection(title: "Slack channels", icon: DaybriefIcon.slack) {
                        SlackChannelsSection(model: model)
                    }
                }

                SettingsSection(title: "AI model", systemImage: "sparkles") {
                    ModelSection(model: model)
                }

                SettingsSection(title: "Daily brief", systemImage: "sun.max") {
                    BriefScheduleSection(model: model)
                }

                SettingsSection(title: "App", systemImage: "gearshape") {
                    AppSection(model: model)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DaybriefTheme.paper)
        .frame(minWidth: 620, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(DaybriefTheme.serifDisplay(30))
                .foregroundStyle(DaybriefTheme.ink)
            Text("Tune what goes into your morning brief.")
                .font(DaybriefTheme.serifBody(14))
                .foregroundStyle(DaybriefTheme.inkSecondary)
        }
    }
}

/// A titled settings group with a leading icon and a soft card body.
private struct SettingsSection<Content: View>: View {
    let title: String
    /// The section glyph. An `Image` rather than an SF Symbol name so a section about
    /// one service can carry that service's own mark (see the Slack channels section).
    let icon: Image
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: Image(systemName: systemImage), content: content)
    }

    init(title: String, icon: Image, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                icon
                    .daybriefIcon(size: 13)
                    .foregroundStyle(DaybriefTheme.accent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.ink)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
            )
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

            Divider().overlay(DaybriefTheme.ink.opacity(0.06))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brief voice & template")
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
