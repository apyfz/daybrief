import DaybriefCore
import LLMKit
import Pipeline
import SwiftUI

/// The settings screen shown once setup is complete: review/retune everything from
/// onboarding without re-running the flow.
///
/// Sections: connected tools (with a per-account Space picker via `model.setSpace`),
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

                SettingsSection(title: "Spaces", systemImage: "square.grid.2x2") {
                    SpacesSection(model: model)
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
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
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
                Image(systemName: connector.symbol)
                    .font(.system(size: 14, weight: .medium))
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

/// One account row: icon, label, connection name, its Space picker, and a
/// destructive Remove button (confirmation-gated).
private struct ConnectionRow: View {
    @Bindable var model: AppModel
    let connection: Connection
    let account: Account

    @State private var selection: String
    @State private var confirmingRemove = false

    init(model: AppModel, connection: Connection, account: Account) {
        self.model = model
        self.connection = connection
        self.account = account
        _selection = State(initialValue: account.spaceKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
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

            Picker("Space", selection: $selection) {
                ForEach(model.spaces) { space in
                    Text(space.displayName).tag(space.key)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)
            .onChange(of: selection) { _, newValue in
                Task { await model.setSpace(accountID: account.id, to: newValue) }
            }

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

    private var symbol: String {
        switch connection.connectorId {
        case .gcal: "calendar"
        case .gmail: "envelope"
        case .slack: "number"
        default: "app.connected.to.app.below.fill"
        }
    }
}

// MARK: - Spaces

/// Lists each space with a Remove (trash) button — disabled when only one space
/// remains — plus an "Add space" row that creates a new space from a typed name.
/// Removing a space re-files its accounts under another space (handled in the model).
private struct SpacesSection: View {
    @Bindable var model: AppModel

    @State private var newSpaceName = ""
    @State private var confirmingRemoval: Space?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.spaces) { space in
                if space != model.spaces.first {
                    Divider().overlay(DaybriefTheme.ink.opacity(0.06))
                }
                spaceRow(space)
            }

            Divider().overlay(DaybriefTheme.ink.opacity(0.06))
            addSpaceRow
        }
        .confirmationDialog(
            "Remove “\(confirmingRemoval?.displayName ?? "")”?",
            isPresented: removalDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let space = confirmingRemoval {
                    Task { await model.removeSpace(key: space.key) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Accounts in this space move to another space. This can't be undone.")
        }
    }

    private func spaceRow(_ space: Space) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DaybriefTheme.ink)
                .frame(width: 28, height: 28)
                .background(DaybriefTheme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))

            Text(space.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DaybriefTheme.ink)

            Spacer(minLength: 12)

            Button {
                confirmingRemoval = space
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(model.spaces.count > 1 ? 0.85 : 0.3))
            }
            .buttonStyle(.plain)
            .disabled(model.spaces.count <= 1)
            .help(model.spaces.count > 1 ? "Remove this space" : "Keep at least one space")
        }
    }

    private var addSpaceRow: some View {
        HStack(spacing: 12) {
            TextField("New space name", text: $newSpaceName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .onSubmit { addSpace() }

            DBSecondaryButton("Add space", systemImage: "plus") {
                addSpace()
            }
            .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer(minLength: 0)
        }
    }

    private func addSpace() {
        let name = newSpaceName
        newSpaceName = ""
        Task { await model.addSpace(displayName: name) }
    }

    /// Bridges the per-space `confirmingRemoval` selection to a `Bool` the
    /// `confirmationDialog(isPresented:)` overload needs.
    private var removalDialogBinding: Binding<Bool> {
        Binding(
            get: { confirmingRemoval != nil },
            set: { presented in if !presented { confirmingRemoval = nil } }
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
                            if !recommendedModels.isEmpty {
                                Section("Recommended") {
                                    ForEach(recommendedModels) { modelRow($0) }
                                }
                            }
                            if showAllModels || recommendedModels.isEmpty {
                                Section(recommendedModels.isEmpty ? "Models" : "All models") {
                                    ForEach(otherModels) { modelRow($0) }
                                }
                            }
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
