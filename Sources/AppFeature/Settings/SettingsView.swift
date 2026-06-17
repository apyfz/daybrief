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

/// Lists each connected account with a per-account Space picker.
private struct ConnectionsSection: View {
    @Bindable var model: AppModel

    private var accounts: [(connection: Connection, account: Account)] {
        model.connections.flatMap { connection in
            connection.accounts.map { (connection, $0) }
        }
    }

    var body: some View {
        if accounts.isEmpty {
            Text("No tools connected. Add Google or Slack from onboarding to fill your brief.")
                .font(.system(size: 13))
                .foregroundStyle(DaybriefTheme.inkSecondary)
        } else {
            ForEach(Array(accounts.enumerated()), id: \.element.account.id) { index, pair in
                ConnectionRow(model: model, connection: pair.connection, account: pair.account)
                if index < accounts.count - 1 {
                    Divider().overlay(DaybriefTheme.ink.opacity(0.06))
                }
            }
        }
    }
}

/// One account row: icon, label, connection name, and its Space picker.
private struct ConnectionRow: View {
    @Bindable var model: AppModel
    let connection: Connection
    let account: Account

    @State private var selection: String

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

// MARK: - Model

/// Provider + model picker. Refreshes the model list when the provider changes.
private struct ModelSection: View {
    @Bindable var model: AppModel

    @State private var models: [ModelInfo] = []
    @State private var isLoading = false

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

            LabeledRow(label: "Model") {
                HStack(spacing: 8) {
                    if models.isEmpty {
                        Text(model.selectedModel.isEmpty ? "Load to choose" : model.selectedModel)
                            .font(.system(size: 13))
                            .foregroundStyle(DaybriefTheme.inkSecondary)
                            .lineLimit(1)
                    } else {
                        Picker("Model", selection: $model.selectedModel) {
                            ForEach(models) { info in
                                Text(info.displayName ?? info.id).tag(info.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                    DBSecondaryButton(isLoading ? "Loading…" : "Refresh", systemImage: "arrow.clockwise") {
                        Task { await refresh() }
                    }
                    .disabled(isLoading)
                }
            }
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        models = await model.availableModels()
        if model.selectedModel.isEmpty, let first = models.first {
            model.selectedModel = first.id
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
            HStack(spacing: 12) {
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
                Text(model.briefTime.encoded)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.ink)
                    .monospacedDigit()
            }
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
