import DaybriefCore
import SwiftUI

/// Onboarding step 3 (design §14.3): assign each connected account to a Space.
///
/// Lists every account across all connections and lets the user file it under a
/// Space (Work / Personal / custom) via `model.setSpace`. Keeping personal and
/// work apart is the whole point of Spaces (design §13) — so a work brief never
/// blends in personal mail.
struct AssignSpacesStep: View {
    @Bindable var model: AppModel

    private var accounts: [(connection: Connection, account: Account)] {
        model.connections.flatMap { connection in
            connection.accounts.map { (connection, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if accounts.isEmpty {
                emptyState
            } else {
                ForEach(accounts, id: \.account.id) { pair in
                    AccountSpaceRow(model: model, connection: pair.connection, account: pair.account)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 14))
                .foregroundStyle(DaybriefTheme.inkSecondary)
            Text("No tools connected yet. Spaces let you keep work and personal apart once you add a connection — you can always come back to this in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One account row with its Space picker.
private struct AccountSpaceRow: View {
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
                .frame(width: 30, height: 30)
                .background(DaybriefTheme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DaybriefTheme.ink)
                Text(connection.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            Spacer(minLength: 12)

            DBSpacePills(
                spaces: model.spaces.map(\.key),
                displayName: { key in displayName(forSpaceKey: key) },
                selection: $selection
            )
        }
        .padding(14)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
        )
        .onChange(of: selection) { _, newValue in
            Task { await model.setSpace(accountID: account.id, to: newValue) }
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

    private func displayName(forSpaceKey key: String) -> String {
        model.spaces.first { $0.key == key }?.displayName ?? key.capitalized
    }
}
