import DaybriefCore
import SwiftUI

/// Onboarding step 2 (design §14.2): the **connect-tools hub**.
///
/// Instead of inline expandable cards, this is a hub of three connector rows —
/// Google Calendar, Gmail, and Slack. Each row shows its icon, name, a one-line
/// "what it surfaces", and a status, and opens a focused, full-screen
/// ``ConnectorDetailScreen`` (a sheet over the onboarding window) with that
/// connector's guided BYO-credential walkthrough.
///
/// Connecting is entirely optional — the wizard's Continue button advances
/// regardless, and a brief can still be written with zero connectors.
struct ConnectToolsStep: View {
    @Bindable var model: AppModel

    /// The connector whose dedicated screen is presented, or `nil` for the hub.
    @State private var selected: OnboardingConnector?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(OnboardingConnector.allCases) { connector in
                DBConnectorRow(
                    symbol: connector.symbol,
                    name: connector.name,
                    surfaces: connector.surfaces,
                    isConnected: isConnected(connector),
                    connectedLabel: connectedLabel(connector)
                ) {
                    selected = connector
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                Text("All optional — connect what you want; add more later in Settings.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(DaybriefTheme.inkSecondary)
            .padding(.top, 2)

            Text("Connected \(connectedCount) of 3.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .accessibilityLabel("\(connectedCount) of 3 tools connected.")
        }
        .sheet(item: $selected) { connector in
            ConnectorDetailScreen(model: model, connector: connector) {
                selected = nil
            }
        }
    }

    // MARK: - Status

    private func connectorID(for connector: OnboardingConnector) -> ConnectorID {
        switch connector {
        case .calendar: .gcal
        case .gmail: .gmail
        case .slack: .slack
        }
    }

    private func isConnected(_ connector: OnboardingConnector) -> Bool {
        let id = connectorID(for: connector)
        return model.connections.contains { $0.connectorId == id && !$0.accounts.isEmpty }
    }

    private func connectedLabel(_ connector: OnboardingConnector) -> String? {
        let id = connectorID(for: connector)
        return model.connections
            .first { $0.connectorId == id && !$0.accounts.isEmpty }?
            .accounts.first?.label
    }

    /// How many of the three connectors are connected (each Google connector counts
    /// on its own now that they have separate screens).
    private var connectedCount: Int {
        OnboardingConnector.allCases.filter { isConnected($0) }.count
    }
}

/// The space key new connections default to during onboarding (first space, else
/// `"work"`). The user re-assigns per account in the next step.
@MainActor
func defaultSpaceKey(_ model: AppModel) -> String {
    model.spaces.first?.key ?? "work"
}
