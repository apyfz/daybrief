# Onboarding: Google Calendar and Gmail (bring-your-own OAuth client)

Daybrief can read your **Google Calendar** and **Gmail** to build your brief.
Because Daybrief runs entirely on your machine with no shared server, it does
not ship a Google application of its own. Instead, you create your own Google
OAuth client — a few minutes of one-time setup in the Google Cloud Console — and
Daybrief uses it on your behalf. Your tokens stay in your macOS Keychain; they
are never sent to anyone but Google.

This guide walks through the whole setup. **Follow every step, especially
setting the consent screen to "In production"** — skipping that step will cause
Daybrief to lose access roughly every 7 days (explained below).

You only do this once. The same client works for both Calendar and Gmail.

---

## Before you start

- You need a Google account (the one whose calendar and mail you want in your
  brief). A personal `@gmail.com` account works; a Google Workspace account may
  require your administrator to allow it.
- You will create a free Google Cloud project. There is no cost for the API
  usage Daybrief needs.

---

## 1. Create a Google Cloud project

1. Go to the **Google Cloud Console**: <https://console.cloud.google.com>.
2. In the project picker at the top, click **New Project**.
3. Give it a name like `Daybrief` and click **Create**.
4. Make sure the new project is selected in the project picker before
   continuing.

## 2. Enable the Calendar and Gmail APIs

1. Open **APIs & Services → Library**:
   <https://console.cloud.google.com/apis/library>.
2. Search for **Google Calendar API**, open it, and click **Enable**.
3. Search for **Gmail API**, open it, and click **Enable**.

Enable both even if you only plan to connect one of them now — it saves a trip
back later.

## 3. Configure the OAuth consent screen

This is the screen Google shows you when you grant Daybrief access. Because you
are the only user of your own client, you do not need Google to review it.

1. Open **APIs & Services → OAuth consent screen**:
   <https://console.cloud.google.com/apis/credentials/consent>.
2. Choose user type:
   - **External** for a personal `@gmail.com` account.
   - **Internal** if you are on a Google Workspace and only your organization
     will use it (Workspace accounts only).
3. Fill in the required fields:
   - **App name:** `Daybrief` (or anything you like — only you will see it).
   - **User support email:** your email.
   - **Developer contact email:** your email.
4. Save and continue through the **Scopes** step — you do **not** need to add
   scopes here; Daybrief requests them at sign-in time.
5. On the **Test users** step (External apps), you may add your own email, but
   the next step makes test users unnecessary.

### Set it to "In production"

This is the most important step.

1. Back on the **OAuth consent screen** overview, find the **Publishing status**
   section.
2. If it says **Testing**, click **Publish app** and confirm to move it to
   **In production**.

> **Why this matters — the 7-day refresh-token expiry.** While an OAuth app is
> in **Testing** status, Google expires its refresh tokens after **7 days**.
> That means Daybrief would silently lose access about once a week and you would
> have to re-authorize. Moving the app to **In production** removes that
> expiry, so your connection keeps working.
>
> You do **not** need to submit your app for Google's verification review.
> Verification is only required when an app serves *other people*. Because you
> are the sole user of your own client, you can run it "In production"
> unverified — you may see an "unverified app" warning the first time you sign
> in, which you can safely proceed past (it is your own app).

## 4. Create a Desktop OAuth client

1. Open **APIs & Services → Credentials**:
   <https://console.cloud.google.com/apis/credentials>.
2. Click **Create Credentials → OAuth client ID**.
3. For **Application type**, choose **Desktop app**. This is required — Daybrief
   uses a local loopback (`127.0.0.1`) redirect, which only the Desktop app
   client type supports. Do **not** pick "Web application" or any other type.
4. Name it `Daybrief Desktop` and click **Create**.
5. Google shows you a **Client ID** and a **Client secret**. Copy both (or use
   **Download JSON**). You will paste them into Daybrief.

> The "client secret" for a Desktop app is not a true secret — desktop clients
> are public, and Daybrief pairs it with PKCE for security. Keep it private
> anyway, but it is normal that it lives in the installed app.

## 5. Paste the client into Daybrief and sign in

1. In Daybrief onboarding, on the **Connect tools** step, choose **Google
   (Calendar / Gmail)**.
2. Paste the **Client ID** and **Client secret** from the previous step.
3. Daybrief opens your browser to Google's sign-in. Choose the account whose
   calendar and mail you want, and approve the requested permissions.
   - If you see an "unverified app" / "Google hasn't verified this app" notice,
     proceed — it is your own client.
4. Daybrief captures the result on a temporary local `127.0.0.1` listener and
   stores your tokens in the Keychain. The connection is now active.

## 6. Assign the connection to a Space

Tag the connection as **Work**, **Personal**, or a custom Space so Daybrief can
filter or split your brief and avoid blending personal mail into a work brief.

---

## Scopes Daybrief requests, and why

Daybrief asks for the **minimum read-only scopes** it needs. It never requests
write access.

- **`calendar.readonly`** — read your calendar events to list today's (and the
  near-future) schedule.
- **`calendar.calendarlist.readonly`** — list which calendars you have, so you
  can pick which ones feed the brief.
- **`gmail.readonly`** — read message metadata (sender, subject, date) and the
  short snippet Gmail returns, to surface what's unread or important. Daybrief
  does **not** request `gmail.send`, `gmail.modify`, or any write scope.

> **Why `gmail.readonly` and not a lighter scope?** Gmail's metadata-only scope
> (`gmail.metadata`) is *also* a restricted scope under Google's rules — it is
> not a lighter-weight escape hatch. So the minimal practical choice for reading
> your mail is `gmail.readonly` combined with your own OAuth client. This is
> exactly why Daybrief is bring-your-own-client: you authorize your own app
> against your own account, and nothing passes through a third party.

---

## Troubleshooting

- **You get signed out / lose access about once a week.** Your consent screen is
  still in **Testing**. Go back to step 3 and set it to **In production**.
- **"redirect_uri_mismatch" or the browser can't reach the callback.** Make sure
  you created a **Desktop app** client (step 4), not a Web application client.
  Desktop clients use the loopback redirect Daybrief expects.
- **"Access blocked: this app's request is invalid" / API not enabled.** Confirm
  both the **Google Calendar API** and **Gmail API** are enabled in the same
  project as your OAuth client (step 2).
- **"Daybrief hasn't been verified by Google."** Expected for your own client.
  Proceed past the warning — you are the developer and the only user.
- **Workspace account won't authorize.** Your organization's admin may restrict
  third-party OAuth or unverified apps. Ask them to allow it, or use the
  **Internal** user type if you control the Workspace.

---

## Notes

- **What leaves your Mac:** your requests go directly to Google's APIs using
  your own client; the message and event data Daybrief reads is then summarized
  by the AI model you chose. No Daybrief server is involved.
- **Deep links into Gmail** (a link from a brief item back to the original
  message) are best-effort and depend on which Google account is active in your
  browser; they may not always land on the exact message.
