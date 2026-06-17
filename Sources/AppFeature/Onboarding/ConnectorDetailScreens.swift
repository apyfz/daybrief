import DaybriefCore
import SwiftUI

/// The three connectors that have a dedicated onboarding screen, used to route the
/// hub's selection into the right detail sheet.
enum OnboardingConnector: Identifiable, CaseIterable {
    case calendar
    case gmail
    case slack

    var id: Self {
        self
    }

    /// The SF Symbol shown on the hub row and the screen header.
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .gmail: "envelope"
        case .slack: "number"
        }
    }

    /// The connector's display name.
    var name: String {
        switch self {
        case .calendar: "Google Calendar"
        case .gmail: "Gmail"
        case .slack: "Slack"
        }
    }

    /// The one-line "what it surfaces" shown on the hub row.
    var surfaces: String {
        switch self {
        case .calendar: "Today and tomorrow's events"
        case .gmail: "Unread and important mail from the last day"
        case .slack: "@-mentions and DMs from the last day"
        }
    }
}

// MARK: - Shared header

/// The shared header for a dedicated connector screen: the connector icon, its
/// name, what it brings into the brief, and a one-line privacy reassurance.
private struct ConnectorScreenHeader: View {
    let connector: OnboardingConnector
    let brings: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: connector.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DaybriefTheme.ink)
                    .frame(width: 52, height: 52)
                    .background(DaybriefTheme.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(connector.name)
                        .font(DaybriefTheme.serifDisplay(24))
                        .foregroundStyle(DaybriefTheme.ink)
                    Text(brings)
                        .font(.system(size: 13))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                Text("Your own credentials — nothing routes through a server.")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DaybriefTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Detail scaffold

/// The fixed-size sheet scaffold every dedicated connector screen shares: a back /
/// done top bar, the scrolling body, and a sticky footer holding the inline error
/// plus the primary connect / done action. Keeps all three screens consistent and
/// the chrome out of the per-connector content.
private struct ConnectorDetailScaffold<Body: View, Footer: View>: View {
    let onClose: () -> Void
    let lastError: String?
    @ViewBuilder let content: Body
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("All tools")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to all tools")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)

            Divider().overlay(DaybriefTheme.ink.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(DaybriefTheme.ink.opacity(0.08))

            VStack(spacing: 12) {
                if let lastError {
                    DBInlineError(message: lastError)
                }
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .background(DaybriefTheme.paper)
        .frame(width: 560, height: 640)
    }
}

// MARK: - Google (Calendar / Gmail)

/// A dedicated screen for one of the two Google connectors (Calendar or Gmail).
///
/// Both share a single Google Desktop OAuth client, so when the other connector is
/// already set up this screen offers a one-tap "Use the same Google client" path
/// (``AppModel/beginConnectGoogleReusingExistingClient(_:space:)``) and otherwise
/// collects the client id + secret for the manual loopback flow.
struct GoogleConnectorScreen: View {
    @Bindable var model: AppModel
    /// Which Google connector this screen sets up.
    let connectorID: ConnectorID
    let connector: OnboardingConnector
    let onClose: () -> Void

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false
    @State private var canReuseExistingClient = false

    private static let consoleURL = URL(string: "https://console.cloud.google.com")!
    private static let authPlatformURL = URL(string: "https://console.cloud.google.com/auth/overview")!
    private static let clientsURL = URL(string: "https://console.cloud.google.com/auth/clients")!

    var body: some View {
        ConnectorDetailScaffold(onClose: onClose, lastError: model.lastError) {
            ConnectorScreenHeader(connector: connector, brings: brings)

            DBDetailSection(title: "Set up your Google client") {
                DBStepList(steps: steps)
            }

            DBDetailSection(title: "What it will read") {
                ForEach(scopeRows, id: \.scope) { row in
                    DBScopeRow(scope: row.scope, why: row.why)
                }
            }

            if canReuseExistingClient {
                reuseCallout
            }

            DBDetailSection(title: canReuseExistingClient ? "…or paste a different client" : "Paste your client") {
                DBLabeledField(label: "Client ID", placeholder: "…apps.googleusercontent.com", text: $clientID)
                DBLabeledField(label: "Client secret", placeholder: "GOCSPX-…", isSecure: true, text: $clientSecret)
            }
        } footer: {
            HStack(spacing: 10) {
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DaybriefTheme.ink)
                        .accessibilityHidden(true)
                    Text("Connected\(connectedLabel.map { " · \($0)" } ?? "")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DaybriefTheme.ink)
                }
                Spacer()
                DBPrimaryButton(
                    title: primaryTitle,
                    isBusy: isConnecting
                ) {
                    Task { await connectManually() }
                }
                .disabled(isConnecting || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task {
            // The reuse offer only applies to the *other* Google connector being set
            // up first; if this very connector is already connected, manual reconnect
            // is the expected path.
            let hasExistingClient = await model.hasExistingGoogleClient()
            canReuseExistingClient = !isConnected && hasExistingClient
        }
    }

    // MARK: Reuse

    private var reuseCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text("You already set up a Google client")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(DaybriefTheme.ink)

            Text("Calendar and Gmail share one Desktop client. Reuse it — no need to re-enter your ID and secret.")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DBPrimaryButton(
                title: isConnecting ? "Opening browser…" : "Use the same Google client",
                isBusy: isConnecting
            ) {
                Task { await connectReusing() }
            }
            .disabled(isConnecting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DaybriefTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DaybriefTheme.accent.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Content

    private var brings: String {
        connectorID == .gcal
            ? "Brings today and tomorrow's events into your brief."
            : "Brings unread and important mail from the last day into your brief."
    }

    private var steps: [DBStep] {
        let api = connectorID == .gcal ? "Google Calendar API" : "Gmail API"
        let scope = connectorID == .gcal ? "calendar.readonly" : "gmail.readonly"
        return [
            DBStep(
                "Open the Google Cloud Console and create a project (or pick an existing one).",
                link: ("Open the Google Cloud Console", Self.consoleURL)
            ),
            DBStep("In APIs & Services → Library, search for and enable the \(api)."),
            DBStep(
                "Open Google Auth Platform and click Get started. Set the app name and your support email (Branding), choose Audience “External,” add your contact email, and finish.",
                link: ("Open Google Auth Platform", Self.authPlatformURL)
            ),
            DBStep(
                "In Google Auth Platform → Audience, click Publish app so the status reads “In production.” While it stays “Testing,” Google expires your sign-in every 7 days.",
                emphasized: true
            ),
            DBStep("In Google Auth Platform → Data Access, click Add or remove scopes and add \(scope)."),
            DBStep(
                "In Google Auth Platform → Clients, click Create client, choose application type Desktop app, and create it. The loopback sign-in only works with the Desktop type.",
                link: ("Open Clients", Self.clientsURL)
            ),
            DBStep("Copy the Client ID and Client secret from the client you just created and paste them below."),
        ]
    }

    private var scopeRows: [(scope: String, why: String)] {
        if connectorID == .gcal {
            return [
                ("calendar.readonly", "Read-only access to your events to list today and tomorrow's schedule."),
            ]
        } else {
            return [
                (
                    "gmail.readonly",
                    "Read-only access to surface unread and important mail. It's a Google restricted scope — which is exactly why you use your own client, so nothing passes through a third party."
                ),
            ]
        }
    }

    // MARK: Status

    private var isConnected: Bool {
        model.connections.contains { $0.connectorId == connectorID && !$0.accounts.isEmpty }
    }

    private var connectedLabel: String? {
        model.connections
            .first { $0.connectorId == connectorID && !$0.accounts.isEmpty }?
            .accounts.first?.label
    }

    private var primaryTitle: String {
        if isConnecting { return "Opening browser…" }
        return isConnected ? "Reconnect" : "Connect \(connector.name)"
    }

    // MARK: Actions

    private func connectManually() async {
        isConnecting = true
        defer { isConnecting = false }
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        await model.beginConnectGoogle(
            connectorID,
            clientID: clientID.trimmingCharacters(in: .whitespaces),
            clientSecret: secret.isEmpty ? nil : secret,
            space: defaultSpaceKey(model)
        )
        if isConnected { onClose() }
    }

    private func connectReusing() async {
        isConnecting = true
        defer { isConnecting = false }
        await model.beginConnectGoogleReusingExistingClient(connectorID, space: defaultSpaceKey(model))
        if isConnected { onClose() }
    }
}

// MARK: - Slack

/// A dedicated screen for connecting Slack via a pasted `xoxp-` user token.
struct SlackConnectorScreen: View {
    @Bindable var model: AppModel
    let connector: OnboardingConnector
    let onClose: () -> Void

    @State private var userToken = ""
    @State private var workspaceLabel = ""
    @State private var isConnecting = false

    private static let appsURL = URL(string: "https://api.slack.com/apps")!

    private static let steps: [DBStep] = [
        DBStep(
            "Click Create New App → From scratch, name it, and pick the workspace you want to read.",
            link: ("Open Slack apps", appsURL)
        ),
        DBStep(
            "Do NOT activate public distribution — keep it an internal, single-workspace app. This keeps the higher rate limits Daybrief needs; distributed apps get throttled to a crawl.",
            emphasized: true
        ),
        DBStep("Under OAuth & Permissions → User Token Scopes, add: search:read, im:history, mpim:history, users:read."),
        DBStep("Click Install to Workspace and approve the permissions."),
        DBStep("Copy the User OAuth Token — it starts with xoxp- (not the xoxb- bot token) — and paste it below."),
    ]

    var body: some View {
        ConnectorDetailScaffold(onClose: onClose, lastError: model.lastError) {
            ConnectorScreenHeader(
                connector: connector,
                brings: "Brings your @-mentions and direct messages from the last day into your brief."
            )

            DBDetailSection(title: "Create your internal Slack app") {
                DBStepList(steps: Self.steps)
            }

            DBDetailSection(title: "What it will read") {
                DBScopeRow(scope: "search:read", why: "Search your messages to find @-mentions of you (needs a user token — bot tokens can't search).")
                DBScopeRow(scope: "im:history", why: "Read your direct-message history from the last day.")
                DBScopeRow(scope: "mpim:history", why: "Read your group direct-message history from the last day.")
                DBScopeRow(scope: "users:read", why: "Resolve user IDs to names so the brief reads naturally.")
            }

            DBDetailSection(title: "Paste your token") {
                DBLabeledField(label: "Workspace name", placeholder: "Crispy Studio", text: $workspaceLabel)
                DBLabeledField(label: "User OAuth token", placeholder: "xoxp-…", isSecure: true, text: $userToken)
                if hasToken, !tokenLooksValid {
                    Text("That doesn't look like a User token — it should start with xoxp-.")
                        .font(.system(size: 12))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }
            }
        } footer: {
            HStack(spacing: 10) {
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DaybriefTheme.ink)
                        .accessibilityHidden(true)
                    Text("Connected\(connectedLabel.map { " · \($0)" } ?? "")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DaybriefTheme.ink)
                }
                Spacer()
                DBPrimaryButton(
                    title: isConnecting ? "Connecting…" : (isConnected ? "Reconnect" : "Connect Slack"),
                    isBusy: isConnecting
                ) {
                    Task { await connect() }
                }
                .disabled(isConnecting || !tokenLooksValid)
            }
        }
    }

    private var hasToken: Bool {
        !userToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var tokenLooksValid: Bool {
        userToken.trimmingCharacters(in: .whitespaces).hasPrefix("xoxp-")
    }

    private var isConnected: Bool {
        model.connections.contains { $0.connectorId == .slack && !$0.accounts.isEmpty }
    }

    private var connectedLabel: String? {
        model.connections
            .first { $0.connectorId == .slack && !$0.accounts.isEmpty }?
            .accounts.first?.label
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        let label = workspaceLabel.trimmingCharacters(in: .whitespaces)
        await model.connectSlack(
            userToken: userToken.trimmingCharacters(in: .whitespaces),
            workspaceLabel: label.isEmpty ? "Slack" : label,
            space: defaultSpaceKey(model)
        )
        if isConnected { onClose() }
    }
}

// MARK: - Routed detail

/// Routes the hub's selected ``OnboardingConnector`` to the right dedicated screen,
/// so the hub presents a single `.sheet(item:)`.
struct ConnectorDetailScreen: View {
    @Bindable var model: AppModel
    let connector: OnboardingConnector
    let onClose: () -> Void

    var body: some View {
        switch connector {
        case .calendar:
            GoogleConnectorScreen(model: model, connectorID: .gcal, connector: connector, onClose: onClose)
        case .gmail:
            GoogleConnectorScreen(model: model, connectorID: .gmail, connector: connector, onClose: onClose)
        case .slack:
            SlackConnectorScreen(model: model, connector: connector, onClose: onClose)
        }
    }
}
