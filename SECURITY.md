# Security

Daybrief is local-first and private by default. This document describes how it handles your data and credentials.

## Where your data lives

- **All data and tokens stay on your machine.** There is no Daybrief server and no third-party token custody. The only network calls Daybrief makes are: directly to the providers you connect (Google, Slack) using *your own* OAuth credentials, and to the AI model endpoint you chose. A local model (Ollama) sends nothing off-box.
- **Secrets are stored in the macOS Keychain** (the data-protection keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`): OAuth access/refresh tokens, your bring-your-own OAuth client id/secret, your AI API key, and the database encryption key. Secrets are never written to logs (all sensitive log interpolations use `privacy: .private`).
- **The local database** is SQLite via GRDB. At-rest encryption (SQLCipher, with the key held in the Keychain) is implemented and available behind a documented build configuration — see `docs/build/grdb-sqlcipher.md`.

## Minimum scopes

Connectors request the least access that still produces a useful brief, and each scope is documented with its reason in the onboarding guides (`docs/onboarding/`). Examples: Google Calendar `calendar.readonly`; Gmail `gmail.readonly`; Slack user-token `search:read`, `im:history`, `mpim:history`, `users:read`.

## Drafting only

Daybrief drafts; it never sends. Any outbound action (replying, posting) is always a separate, explicit confirmation — it is never automatic.

## What leaves your machine

When a brief is generated, the normalized items behind it (e.g. subjects, snippets, event titles, message text) are sent to the AI model you selected so it can write the brief. If that model is a cloud provider (OpenRouter/Anthropic/OpenAI/Google), that content goes to the provider under your account. Choose a local model (Ollama) if you want nothing to leave the device.

## The desktop widget snapshot (a scoped relaxation)

The optional desktop widget runs in a separate, sandboxed process that cannot open the
encrypted database or read the Keychain. To feed it, the app writes a small snapshot of
**today's brief** into the shared App Group container
(`~/Library/Group Containers/<TeamID>.co.daybrief.shared/`):

- `latest-brief.json` — the current brief (masthead, lede, lead, section headlines +
  details, already link-safety-checked source URLs, the factual colophon, mood, hero
  metadata).
- `latest-hero.png` — the edition's public-domain hero painting, downsampled.

This is a **conscious, scoped relaxation** of the SQLCipher "encrypted at rest" posture:
the snapshot is plaintext on disk, so any process running as you (or a backup) can read
it. It is mitigated as follows:

- The container is **scoped to your Apple Developer Team ID** — only Daybrief-signed
  processes from the same team carry the entitlement to read it; it is not world-readable.
- The snapshot contains **only the already-redacted, display-safe fields the brief panel
  itself shows**. It never contains OAuth tokens, your AI API key, the SQLCipher database
  key, raw connector payloads, or full message bodies.

If you do not add the widget, the snapshot is still written (it's cheap and keeps the
widget instant when added). A future option to disable it entirely can gate the writer.

## Reporting a vulnerability

Please report security issues privately to the maintainers rather than opening a public issue. (Set up a disclosure contact / `SECURITY` advisory before public release.)
