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

## Reporting a vulnerability

Please report security issues privately to the maintainers rather than opening a public issue. (Set up a disclosure contact / `SECURITY` advisory before public release.)
