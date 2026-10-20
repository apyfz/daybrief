import AppKit
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
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connected tools").font(.system(size: 22, weight: .semibold))
                    Text("What Daybrief reads each morning.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                connectorList
            }
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
                DaybriefIcon.coloredConnector(connector.connectorID)
                    .daybriefIcon(size: 26)
                    .foregroundStyle(DaybriefTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.black.opacity(0.06), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(connector.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DaybriefTheme.ink)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }

                Spacer(minLength: 12)

                if !isConnected {
                    Text("Set up")
                        .font(.system(size: 11))
                        .foregroundStyle(DaybriefTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DaybriefTheme.accent.opacity(0.35), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            .padding(.vertical, 12)
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
        var parts = [first.label == connector.name ? "Connected" : first.label]
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
    @State private var showSetup = false

    private var isConnected: Bool {
        model.connections.contains { $0.connectorId == connector.connectorID && !$0.accounts.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                    Text("All tools")
                        .font(.system(size: 12))
                }
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityLabel("Back to all tools")

            HStack(spacing: 12) {
                connector.icon
                    .daybriefIcon(size: 32)
                    .frame(width: 52, height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(connector.name).font(.system(size: 22, weight: .semibold))
                    Text(connector.surfaces).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

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
                        .padding(.vertical, 10)
                }
            }

            if isConnected {
                DisclosureGroup("Add or reconnect an account", isExpanded: $showSetup) {
                    setup.padding(.top, 16)
                }
                .font(.system(size: 13, weight: .medium))
            } else {
                setup
            }
        }
    }

    private var setup: some View {
        ConnectorDetailScreen(model: model, connector: connector, onClose: onBack)
            .environment(\.connectorChrome, .inline)
    }
}

/// The Brief pane: when the edition fires, and the prompt/template that gives it voice.
struct BriefPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BriefScheduleSection(model: model)
            SettingsRowDivider()
            BriefVoiceSection(model: model)
        }
        .padding(.top, 8)
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
        AppSection(model: model)
            .padding(.top, 8)
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
                    .daybriefIcon(size: 20)
                    .foregroundStyle(DaybriefTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(DaybriefTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 5) {
                    Text(connector.name)
                        .font(.system(size: 14, weight: .medium))
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
            DaybriefIcon.coloredConnector(connection.connectorId)
                .daybriefIcon(size: 20)
                .foregroundStyle(DaybriefTheme.ink)
                .frame(width: 40, height: 40)
                .background(DaybriefTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                Text(account.label)
                    .font(.system(size: 13))
                    .foregroundStyle(DaybriefTheme.ink)
                Text("Connected")
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            Spacer(minLength: 12)

            Button {
                confirmingRemove = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
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
        .padding(.vertical, 10)
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
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup {
                LabeledRow(label: "Provider") {
                    Picker("Provider", selection: $model.selectedProvider) {
                        ForEach(Provider.allCases) { provider in
                            Text(displayName(provider)).tag(provider)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.vertical, 10)

                if model.selectedProvider.requiresAPIKey {
                    SettingsRowDivider()
                    LabeledRow(label: "API key") {
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("Enter a new API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            Text("Leave blank to keep your saved key.")
                                .font(.system(size: 11))
                                .foregroundStyle(DaybriefTheme.inkSecondary)
                        }
                    }
                    .padding(.vertical, 12)
                }

                SettingsRowDivider()
                LabeledRow(label: "Model") {
                    if models.isEmpty {
                        Text(model.selectedModel.isEmpty ? "Load models to choose one" : model.selectedModel)
                            .font(.system(size: 12))
                            .foregroundStyle(DaybriefTheme.inkSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Picker("Model", selection: $model.selectedModel) {
                            ForEach(visibleModels) { modelRow($0) }
                        }
                        .labelsHidden()
                        .onChange(of: model.selectedModel) { _, _ in
                            Task { await model.persistSelectedModel() }
                        }
                    }
                }
                .padding(.vertical, 12)
            }

            HStack {
                if !recommendedModels.isEmpty, !otherModels.isEmpty {
                    Toggle("Show all models", isOn: $showAllModels)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
                Spacer()
                Button(isLoading ? "Loading…" : "Save & load models") {
                    Task { await saveAndLoad() }
                }
                .controlSize(.regular)
                .disabled(isLoading)
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

/// A native, keyboard-editable time field with a readable size and visible stepper.
private struct DeliveryTimePicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.font = .monospacedDigitSystemFont(ofSize: 26, weight: .medium)
        picker.drawsBackground = true
        picker.backgroundColor = .white
        picker.isBezeled = true
        picker.setAccessibilityLabel("Delivery time")
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.dateValue != selection { picker.dateValue = selection }
    }

    final class Coordinator: NSObject {
        var parent: DeliveryTimePicker
        init(_ parent: DeliveryTimePicker) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.selection = sender.dateValue }
    }
}

// MARK: - Schedule

/// The daily brief-time picker.
private struct BriefScheduleSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Morning delivery")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DaybriefTheme.ink)
                Text("Your brief is prepared each day at this time. If your Mac is asleep, it catches up when you wake it.")
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DaybriefTheme.ink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Every day at")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    DeliveryTimePicker(selection: timeBinding)
                        .frame(width: 180, height: 38)
                }
                Spacer(minLength: 12)
                Text("Local time")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.09)))
        }
        .padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Writing style")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DaybriefTheme.ink)
            Text("Make the brief your own. Edit the prompt for its voice and priorities, or the template for its layout.")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.openPromptTemplateInFinder()
            } label: {
                Label("Open prompt & template", systemImage: "folder")
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - App

/// Launch-at-login toggle and the prompt/template editor button.
private struct AppSection: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Launch at login")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DaybriefTheme.ink)
                Text("Open Daybrief automatically when you sign in. It stays in your menu bar, ready for your next brief.")
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Launch at login", isOn: launchBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
        }
        .padding(.vertical, 12)
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
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DaybriefTheme.ink)
                .frame(width: 76, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
