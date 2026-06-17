# Onboarding: Slack (internal app + pasted user token)

Daybrief can read your Slack **mentions** and **direct messages** so they show
up in your brief. As with Google, Daybrief runs on your machine with no shared
server, so you create your own Slack app, install it to your workspace, and
paste your personal user token into Daybrief. The token stays in your macOS
Keychain.

Slack is simpler than Google here — there is no in-app OAuth dance. You generate
a token in Slack's app config page and paste it in.

> **Important: do NOT activate public distribution for your app.** Keep it an
> internal, single-workspace app. The reason is rate limits, explained below —
> getting this wrong will throttle Daybrief to the point of being unusable.

You do this once per workspace you want to include.

---

## 1. Create a Slack app

1. Go to **<https://api.slack.com/apps>** and click **Create New App**.
2. Choose **From scratch**.
3. Give it a name like `Daybrief` and select the **workspace** you want to read.
4. Click **Create App**.

## 2. Add user-token scopes

Daybrief reads Slack **as you**, so it needs **user-token** scopes (not
bot-token scopes). Bot tokens cannot search messages, which is how Daybrief
finds your mentions.

1. In your app's settings, open **OAuth & Permissions**.
2. Scroll to **Scopes → User Token Scopes** (be sure you are editing **User**
   token scopes, not Bot token scopes).
3. Add these scopes:
   - **`search:read`** — search your messages to find mentions of you. This
     requires a user token; bot tokens cannot search.
   - **`im:history`** — read your direct-message history.
   - **`mpim:history`** — read your group direct-message history.
   - **`users:read`** — resolve user IDs to names so the brief reads naturally.

These are the minimum scopes. (If you later want Daybrief to read specific named
channels, you can add `channels:history` / `groups:history` — not needed for
mentions and DMs.)

## 3. Install the app to your workspace

1. Still under **OAuth & Permissions**, click **Install to Workspace** (or
   **Reinstall** if you changed scopes).
2. Review the permissions and click **Allow**.

## 4. Do NOT activate public distribution

This is the step people get wrong.

1. Leave the app as an **internal**, single-workspace app. Do not go to
   **Manage Distribution** and activate public distribution, and do not submit
   it to the Slack Marketplace.

> **Why — the rate-limit reason.** Internal (single-workspace) apps keep Slack's
> normal Tier-3 request limits, which are plenty for Daybrief. In 2025 Slack
> sharply throttled **non-Marketplace distributed** apps — down to roughly **1
> request per minute** and a tiny message allowance. If you activate public
> distribution on your app without being a Marketplace app, Daybrief will get
> throttled to that crawl and your brief will be slow or empty. Keeping the app
> internal avoids this entirely. (Daybrief detects this throttle and will warn
> you to set your app back to internal if it sees it.)

## 5. Copy the User OAuth Token

1. After installing, the **OAuth & Permissions** page shows your tokens.
2. Copy the **User OAuth Token** — it starts with **`xoxp-`**.
   - Be sure you copy the **User** token (`xoxp-`), **not** the Bot User OAuth
     Token (`xoxb-`). Daybrief needs the `xoxp-` user token to search your
     mentions.

Treat this token like a password — it can read your Slack messages.

## 6. Paste the token into Daybrief

1. In Daybrief onboarding, on the **Connect tools** step, choose **Slack**.
2. Paste your **`xoxp-...`** User OAuth Token.
3. Daybrief verifies it and stores it in the Keychain.

## 7. Assign the connection to a Space

Tag the Slack connection as **Work**, **Personal**, or a custom Space so it lands
in the right brief.

---

## What Daybrief reads

- **Mentions of you**, via Slack's message search (this is why `search:read` and
  a user token are required).
- **Direct messages and group DMs** from the last day's window.

Daybrief reads only; it never sends messages or changes anything in your Slack.

---

## Troubleshooting

- **Brief shows few or no Slack items, or feels very slow.** Your app may have
  been switched to distributed. Check **Manage Distribution** and make sure
  public distribution is **not** activated; keep the app internal (see step 4),
  then try again.
- **"missing_scope" or no mentions appear.** Confirm the scopes are under **User
  Token Scopes** (not Bot Token Scopes) and that you **reinstalled** the app
  after adding them (step 3).
- **The token doesn't work.** Make sure you copied the **`xoxp-`** User OAuth
  Token, not the **`xoxb-`** Bot token.

---

## Notes

- **One app per workspace:** repeat these steps for each Slack workspace you want
  in your brief; each produces its own `xoxp-` token.
- **What leaves your Mac:** Daybrief's calls go directly to Slack with your
  token; the message content it reads is then summarized by the AI model you
  chose. No Daybrief server is involved.
