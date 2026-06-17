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

    /// The underlying connector id this onboarding screen sets up.
    var connectorID: ConnectorID {
        switch self {
        case .calendar: .gcal
        case .gmail: .gmail
        case .slack: .slack
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

// MARK: - Shared callouts

/// A friendly one-line "how long this takes" framing shown under the header.
private struct ConnectorIntroLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(DaybriefTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A calm, neutral "here's what you'll see and it's fine" callout — used for
/// Google's scary "unverified app" warning and Slack's permissions prompt, so the
/// screen doesn't scare a non-technical user into bailing out.
private struct ExpectScreenCallout: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(DaybriefTheme.ink)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DaybriefTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DaybriefTheme.ink.opacity(0.12), lineWidth: 1)
        )
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
/// The walkthrough is split into short, friendly "parts" (rather than one long
/// list), names the exact values to type, and warns up front about Google's
/// "unverified app" screen so a non-technical user isn't scared off. Calendar and
/// Gmail share one Google Desktop OAuth client, so when the other connector is
/// already set up this screen offers a one-tap "Use the same Google client" path.
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

            ConnectorIntroLine(text: "This takes about five minutes, and you only do it once. Just follow each part in order — we'll tell you exactly what to type and click.")

            DBDetailSection(title: "What Daybrief will read") {
                ForEach(scopeRows, id: \.scope) { row in
                    DBScopeRow(scope: row.scope, why: row.why)
                }
            }

            if canReuseExistingClient {
                reuseCallout
            }

            DBDetailSection(title: "Part 1 · Create your project") {
                DBStepList(steps: part1Steps)
            }
            DBDetailSection(title: "Part 2 · Turn on the \(apiShortName)") {
                DBStepList(steps: part2Steps)
            }
            DBDetailSection(title: "Part 3 · Set up the sign-in screen") {
                DBStepList(steps: part3Steps)
            }
            DBDetailSection(title: "Part 4 · Make it permanent") {
                DBStepList(steps: part4Steps)
            }
            DBDetailSection(title: "Part 5 · Allow read access") {
                DBStepList(steps: part5Steps)
            }
            DBDetailSection(title: "Part 6 · Create the key Daybrief uses") {
                DBStepList(steps: part6Steps)
            }

            DBDetailSection(title: canReuseExistingClient ? "…or paste a different client" : "Part 7 · Paste it into Daybrief") {
                DBLabeledField(label: "Client ID", placeholder: "…apps.googleusercontent.com", text: $clientID)
                DBLabeledField(label: "Client secret", placeholder: "GOCSPX-…", isSecure: true, text: $clientSecret)
            }

            ExpectScreenCallout(
                title: "When you sign in, Google will warn you — that's expected",
                message: "Google shows a red “Google hasn't verified this app” screen and even labels it “(unsafe).” Don't let it scare you off — it appears because this is your own personal app, and personal apps aren't submitted for Google's review. To continue: click Advanced (or “Hide Advanced”), then click “Go to Daybrief (unsafe).” The “(unsafe)” is Google's blanket wording for any unverified app — it does not mean Daybrief is unsafe. Your sign-in stays on your Mac."
            )
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

            Text("Calendar and Gmail share one Google client. Reuse the one you already made — no need to do any of the setup below again.")
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

    /// Short name used in headings, e.g. "Google Calendar API" / "Gmail API".
    private var apiShortName: String {
        connectorID == .gcal ? "Google Calendar API" : "Gmail API"
    }

    private var scopeName: String {
        connectorID == .gcal ? "calendar.readonly" : "gmail.readonly"
    }

    private var part1Steps: [DBStep] {
        [
            DBStep(
                "Open the Google Cloud Console and sign in with the Google account whose data you want.",
                link: ("Open the Google Cloud Console", Self.consoleURL)
            ),
            DBStep("Click the project menu at the very top, then “New Project.” For the name, type Daybrief and click Create. Make sure “Daybrief” is selected at the top before moving on."),
        ]
    }

    private var part2Steps: [DBStep] {
        [
            DBStep("In the left menu go to “APIs & Services” → “Library.” Search for \(apiShortName), open it, and click Enable."),
        ]
    }

    private var part3Steps: [DBStep] {
        [
            DBStep(
                "Open “Google Auth Platform” and click “Get started.”",
                link: ("Open Google Auth Platform", Self.authPlatformURL)
            ),
            DBStep("App name: type Daybrief. User support email: pick your own email. Click Next."),
            DBStep("Audience: choose “External.” Click Next."),
            DBStep("Contact information: enter your email, click Next, agree to the policy, then click Create."),
        ]
    }

    private var part4Steps: [DBStep] {
        [
            DBStep(
                "Open “Audience” in the left menu and click “Publish app” so the status reads “In production.” If you skip this, Google will sign you out every 7 days.",
                emphasized: true
            ),
        ]
    }

    private var part5Steps: [DBStep] {
        [
            DBStep("Open “Data Access” in the left menu, click “Add or remove scopes,” add \(scopeName), then click Update and Save."),
        ]
    }

    private var part6Steps: [DBStep] {
        [
            DBStep(
                "Open “Clients” in the left menu and click “Create client.”",
                link: ("Open Clients", Self.clientsURL)
            ),
            DBStep("Application type: choose “Desktop app.” Name: type Daybrief Desktop. Click Create. (Desktop is required — the sign-in won't work with any other type.)"),
            DBStep("A box pops up with your Client ID and Client secret. Copy both — you'll paste them just below."),
        ]
    }

    private var scopeRows: [(scope: String, why: String)] {
        if connectorID == .gcal {
            return [
                ("calendar.readonly", "Read-only access to your events, to list today and tomorrow's schedule. Daybrief can never change your calendar."),
            ]
        } else {
            return [
                (
                    "gmail.readonly",
                    "Read-only access to surface unread and important mail. Daybrief can never send or delete anything. (It's a Google “restricted” scope — which is exactly why you use your own client, so nothing passes through a third party.)"
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

/// A dedicated screen for connecting Slack via a pasted `xoxp-` user token, split
/// into short friendly parts with the exact values to type.
struct SlackConnectorScreen: View {
    @Bindable var model: AppModel
    let connector: OnboardingConnector
    let onClose: () -> Void

    @State private var userToken = ""
    @State private var workspaceLabel = ""
    @State private var isConnecting = false

    private static let appsURL = URL(string: "https://api.slack.com/apps")!

    private static let part1Steps: [DBStep] = [
        DBStep(
            "Open Slack's app page and sign in.",
            link: ("Open Slack apps", appsURL)
        ),
        DBStep("Click “Create New App” → “From scratch.” App Name: type Daybrief. Pick the workspace you want in your brief. Click “Create App.”"),
    ]

    private static let part2Steps: [DBStep] = [
        DBStep(
            "Do NOT click “Activate Public Distribution” (it's under “Manage Distribution” — just leave it alone). Keeping the app internal is what stops Slack from throttling it to a crawl.",
            emphasized: true
        ),
    ]

    private static let part3Steps: [DBStep] = [
        DBStep("In the left menu open “OAuth & Permissions.” Scroll to “Scopes,” and under “User Token Scopes” (NOT “Bot Token Scopes”) add all six: search:read, im:read, im:history, mpim:read, mpim:history, users:read."),
    ]

    private static let part4Steps: [DBStep] = [
        DBStep("Scroll back to the top of “OAuth & Permissions” and click “Install to Workspace,” then “Allow.”"),
    ]

    private static let part5Steps: [DBStep] = [
        DBStep("Back on “OAuth & Permissions,” copy the “User OAuth Token” at the top — it starts with xoxp- (not the xoxb- bot token). Paste it below."),
    ]

    var body: some View {
        ConnectorDetailScaffold(onClose: onClose, lastError: model.lastError) {
            ConnectorScreenHeader(
                connector: connector,
                brings: "Brings your @-mentions and direct messages from the last day into your brief."
            )

            ConnectorIntroLine(text: "About two minutes, once. Follow each part — we'll tell you exactly what to type and click.")

            DBDetailSection(title: "What Daybrief will read") {
                DBScopeRow(scope: "search:read", why: "Find @-mentions of you (a user token is required — bot tokens can't search).")
                DBScopeRow(scope: "im:read", why: "List your direct-message conversations.")
                DBScopeRow(scope: "im:history", why: "Read your direct-message history from the last day.")
                DBScopeRow(scope: "mpim:read", why: "List your group direct-message conversations.")
                DBScopeRow(scope: "mpim:history", why: "Read your group direct-message history from the last day.")
                DBScopeRow(scope: "users:read", why: "Turn user IDs into names so the brief reads naturally.")
            }

            DBDetailSection(title: "Part 1 · Create your app") {
                DBStepList(steps: Self.part1Steps)
            }
            DBDetailSection(title: "Part 2 · Keep it private") {
                DBStepList(steps: Self.part2Steps)
            }
            DBDetailSection(title: "Part 3 · Choose what it can read") {
                DBStepList(steps: Self.part3Steps)
            }
            DBDetailSection(title: "Part 4 · Install it") {
                DBStepList(steps: Self.part4Steps)
            }
            DBDetailSection(title: "Part 5 · Copy your token") {
                DBStepList(steps: Self.part5Steps)
            }

            DBDetailSection(title: "Part 6 · Paste it into Daybrief") {
                DBLabeledField(label: "Workspace name", placeholder: "e.g. Crispy Studio", text: $workspaceLabel)
                DBLabeledField(label: "User OAuth token", placeholder: "xoxp-…", isSecure: true, text: $userToken)
                if hasToken, !tokenLooksValid {
                    Text("That doesn't look like a User token — it should start with xoxp-.")
                        .font(.system(size: 12))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }
            }

            ExpectScreenCallout(
                title: "Slack will ask you to “Allow” — that's normal",
                message: "When you click Install to Workspace, Slack shows a permissions screen listing what Daybrief can see (your messages, mentions, names). That's the expected, sanctioned flow — just click Allow. It's your own app in your own workspace; nothing routes through anyone else."
            )
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
