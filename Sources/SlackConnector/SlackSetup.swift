import ConnectorKit
import Foundation

/// Static onboarding copy for the Slack connector's pasted-token auth strategy.
///
/// Kept separate from ``SlackConnector`` so the (long) setup guide doesn't crowd the
/// fetch/normalize logic. The guide steers the user to create an **internal** app
/// (public distribution never activated — distributed apps are barred from
/// `search.messages` *and* throttled to Tier-1) and to copy the **User** OAuth token
/// (`xoxp-`), not a bot token (`xoxb-`, which cannot search).
enum SlackSetup {
    /// The minimum User Token Scopes the connector needs. `im:read`/`mpim:read` back
    /// `conversations.info`'s per-user `unread_count_display`, which is how DMs are
    /// surfaced by unread state rather than a time window.
    static let requiredScopes = ["search:read", "im:read", "im:history", "mpim:read", "mpim:history", "users:read"]

    /// The `TokenSpec` carried by ``AuthStrategy/pastedUserToken(_:)``.
    static var tokenSpec: TokenSpec {
        TokenSpec(setupInstructions: instructions, tokenPrefixHint: "xoxp-")
    }

    /// Human-facing, step-by-step setup guide shown in the connect UI.
    static let instructions = """
    Connect Slack with your own internal app (one workspace, ~3 minutes):

    1. Go to api.slack.com/apps → "Create New App" → "From scratch". Name it \
    (e.g. "Daybrief") and pick your workspace.
    2. Open "OAuth & Permissions". Under "User Token Scopes" (NOT Bot Token Scopes) \
    add: search:read, im:read, im:history, mpim:read, mpim:history, users:read.
    3. Do NOT click "Activate Public Distribution" — leave it off. Daybrief needs an \
    internal, single-workspace app; a distributed app is blocked from reading mentions \
    and is rate-limited to ~1 request per minute.
    4. Click "Install to Workspace" and approve.
    5. Back on "OAuth & Permissions", copy the "User OAuth Token" — it starts with \
    "xoxp-". (Do not copy the Bot token, which starts with "xoxb-" and cannot read \
    mentions.) Paste it here.
    """
}
