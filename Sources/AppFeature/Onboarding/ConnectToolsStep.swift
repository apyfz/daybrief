import DaybriefCore
import SwiftUI

/// Onboarding step 2 (design §14.2): connect tools, each optional, each with its
/// own guided bring-your-own-credential walkthrough.
///
/// - Google (Calendar + Gmail): guided Cloud-project / Desktop-OAuth-client setup
///   (including setting the consent screen to "In production" to dodge the 7-day
///   refresh-token death), then `model.beginConnectGoogle` runs the loopback flow.
/// - Slack: guided internal-app creation, then the user pastes the `xoxp-` User
///   token into `model.connectSlack`.
struct ConnectToolsStep: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GoogleConnectCard(model: model)
            SlackConnectCard(model: model)

            Text("Connected \(connectedCount) of 2. You can skip any of these and add them later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
        }
    }

    private var connectedCount: Int {
        let connected = Set(
            model.connections
                .filter { !$0.accounts.isEmpty }
                .map(\.connectorId)
        )
        // Google (gcal/gmail) counts as one tool; Slack as the other.
        var n = 0
        if connected.contains(.gcal) || connected.contains(.gmail) { n += 1 }
        if connected.contains(.slack) { n += 1 }
        return n
    }
}

/// The Google (Calendar / Gmail) connect card with its BYO-client guidance.
private struct GoogleConnectCard: View {
    @Bindable var model: AppModel

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false

    private static let steps: [String] = [
        "Open console.cloud.google.com and create a new project (or pick an existing one).",
        "Under APIs & Services → Library, enable the Google Calendar API and the Gmail API.",
        "Go to APIs & Services → OAuth consent screen. Choose External, fill the required fields, then click Publish app so its status reads \"In production\" — this is what stops Google expiring your access every 7 days.",
        "Under Credentials → Create credentials → OAuth client ID, choose application type Desktop app, and create it.",
        "Copy the client ID and client secret from the dialog and paste them below.",
    ]

    var body: some View {
        ConnectCard(
            symbol: "calendar",
            title: "Google — Calendar & Gmail",
            blurb: "Read today's events and your unread/important mail. Uses your own Google OAuth client, so your data never passes through anyone else.",
            isConnected: isConnected,
            connectedLabel: connectedLabel
        ) {
            DBGuidedSteps(title: "Set up your Google OAuth client", steps: Self.steps)

            DBLabeledField(label: "Client ID", placeholder: "…apps.googleusercontent.com", text: $clientID)
            DBLabeledField(label: "Client secret", placeholder: "GOCSPX-…", isSecure: true, text: $clientSecret)

            HStack(spacing: 10) {
                DBPrimaryButton(
                    title: isConnecting ? "Opening browser…" : (isConnected ? "Reconnect" : "Connect Google"),
                    isBusy: isConnecting
                ) {
                    Task { await connect() }
                }
                .disabled(isConnecting || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var isConnected: Bool {
        model.connections.contains {
            ($0.connectorId == .gcal || $0.connectorId == .gmail) && !$0.accounts.isEmpty
        }
    }

    private var connectedLabel: String? {
        return model.connections
            .first { ($0.connectorId == .gcal || $0.connectorId == .gmail) && !$0.accounts.isEmpty }?
            .accounts.first?.label
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        // Calendar + Gmail share one Desktop client; connect both with the same creds.
        await model.beginConnectGoogle(
            .gcal,
            clientID: clientID.trimmingCharacters(in: .whitespaces),
            clientSecret: secret.isEmpty ? nil : secret,
            space: defaultSpaceKey(model)
        )
        await model.beginConnectGoogle(
            .gmail,
            clientID: clientID.trimmingCharacters(in: .whitespaces),
            clientSecret: secret.isEmpty ? nil : secret,
            space: defaultSpaceKey(model)
        )
    }
}

/// The Slack connect card with its internal-app guidance + token paste field.
private struct SlackConnectCard: View {
    @Bindable var model: AppModel

    @State private var userToken = ""
    @State private var workspaceLabel = ""
    @State private var isConnecting = false

    private static let steps: [String] = [
        "Open api.slack.com/apps and click Create New App → From scratch. Name it and pick your workspace.",
        "Keep it internal — never click \"Activate Public Distribution\". Internal apps keep the higher rate limits Daybrief needs.",
        "Under OAuth & Permissions → User Token Scopes, add: search:read, im:history, mpim:history, users:read (and groups:history if you read private channels).",
        "Click Install to Workspace and approve.",
        "Back on OAuth & Permissions, copy the User OAuth Token (it starts with xoxp-) and paste it below.",
    ]

    var body: some View {
        ConnectCard(
            symbol: "number",
            title: "Slack",
            blurb: "Surface your @-mentions and direct messages from the last day. You paste your own User token — no Slack OAuth dance.",
            isConnected: isConnected,
            connectedLabel: connectedLabel
        ) {
            DBGuidedSteps(title: "Create your internal Slack app", steps: Self.steps)

            DBLabeledField(label: "Workspace name", placeholder: "Crispy Studio", text: $workspaceLabel)
            DBLabeledField(label: "User OAuth token", placeholder: "xoxp-…", isSecure: true, text: $userToken)

            DBPrimaryButton(
                title: isConnecting ? "Connecting…" : (isConnected ? "Reconnect" : "Connect Slack"),
                isBusy: isConnecting
            ) {
                Task { await connect() }
            }
            .disabled(isConnecting || !canConnect)
        }
    }

    private var canConnect: Bool {
        userToken.trimmingCharacters(in: .whitespaces).hasPrefix("xoxp-")
    }

    private var isConnected: Bool {
        model.connections.contains { $0.connectorId == .slack && !$0.accounts.isEmpty }
    }

    private var connectedLabel: String? {
        model.connections.first { $0.connectorId == .slack && !$0.accounts.isEmpty }?
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
    }
}

/// A reusable connector card: header (icon, title, status), blurb, and the
/// connector-specific form revealed in `content`.
private struct ConnectCard<Content: View>: View {
    let symbol: String
    let title: String
    let blurb: String
    let isConnected: Bool
    let connectedLabel: String?
    @ViewBuilder let content: Content

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DaybriefTheme.ink)
                        .frame(width: 34, height: 34)
                        .background(DaybriefTheme.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DaybriefTheme.ink)
                        Text(blurb)
                            .font(.system(size: 12))
                            .foregroundStyle(DaybriefTheme.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)

                    if isConnected {
                        statusBadge
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
            Text(connectedLabel ?? "Connected")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DaybriefTheme.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(DaybriefTheme.accent.opacity(0.5), in: Capsule())
    }
}

/// The space key new connections default to during onboarding (first space, else
/// `"work"`). The user re-assigns per account in the next step.
@MainActor
private func defaultSpaceKey(_ model: AppModel) -> String {
    model.spaces.first?.key ?? "work"
}
