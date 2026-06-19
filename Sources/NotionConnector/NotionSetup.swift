import ConnectorKit
import Foundation

/// Static onboarding copy for the Notion connector's pasted-token auth strategy.
///
/// Kept separate from ``NotionConnector`` so the setup guide doesn't crowd the
/// fetch/normalize logic. The guide steers the user to create their own **internal
/// integration** (workspace-private) and paste its secret. The user decides exactly
/// which databases the integration can read by sharing only those with it — the
/// connector then auto-discovers task-shaped databases among them, so there is no
/// database id or property mapping to configure.
enum NotionSetup {
    /// The `TokenSpec` carried by ``AuthStrategy/pastedUserToken(_:)``.
    ///
    /// No prefix hint: internal integration secrets come in two valid shapes — the
    /// newer `ntn_…` and the legacy `secret_…` — so validating against a single prefix
    /// would wrongly reject one of them. The connector instead verifies the token by
    /// calling the API on connect.
    static var tokenSpec: TokenSpec {
        TokenSpec(setupInstructions: instructions, tokenPrefixHint: nil)
    }

    /// Human-facing, step-by-step setup guide shown in the connect UI.
    static let instructions = """
    Connect Notion with your own integration (about two minutes):

    1. Go to notion.so/my-integrations → "New integration". Give it a name (e.g. "Daybrief").
    2. For "Authentication method", choose "Access token" (a workspace-scoped token — \
    not OAuth). Under "Installable in", pick your workspace, then save.
    3. Open the integration and copy its access token (it starts with "ntn_"). Paste it here.
    4. Open the Notion database that holds your tasks. Click the "•••" menu (top-right) \
    → "Connections" → choose your integration. Do this for each database you want Daybrief \
    to read.

    Daybrief reads only what you share with the integration, and only surfaces tasks \
    that are due today or overdue and not yet done.
    """
}
