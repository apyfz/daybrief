# Daybrief

A local-first, private-by-default **daily brief** for macOS. Daybrief lives in your menu bar, and each morning it assembles a single editorial brief from the tools you've connected — what's on today, what slipped overnight, what's worth pushing forward — written in your chosen AI model and rendered like a small morning periodical, not a wall of notifications.

Everything runs on your machine. The only thing that ever leaves is the brief content you send to the AI model you picked (and a local model sends nothing off-box).

> Status: **v0, macOS only.** Native Swift / SwiftUI. Connectors: Google Calendar, Gmail (multi-account), Slack. Bring-your-own AI key (OpenRouter recommended; direct providers and local Ollama supported). Windows/Linux would be a separate native effort.

## The brief

It reads as an edition — a masthead, a public-domain painting, a short editorial lede, and a few prioritized, context-rich items with a clear next action — rather than a dashboard. Quiet days are stated plainly, not padded. It only ever *drafts*; sending anything is always a separate, explicit step.

## Requirements

- macOS 26 (Tahoe)
- Xcode 26 / Swift 6.2 (Swift 6 language mode, strict concurrency)
- Apple Silicon

## Build & run

```sh
# Library + engine (all modules), with tests:
swift build
swift test

# The menu-bar app bundle:
brew install xcodegen          # one-time
xcodegen generate              # produces Daybrief.xcodeproj
open Daybrief.xcodeproj         # then Run, or:
xcodebuild -project Daybrief.xcodeproj -scheme Daybrief -configuration Debug build
```

The app is a menu-bar accessory (no Dock icon). On first launch it walks you through entering an AI key and connecting tools; with just an AI key and no connectors it will still produce a calm "quiet day" brief.

## Architecture

A thin Xcode app target over local Swift packages, each independently testable. Dependencies point inward toward `DaybriefCore`:

- **`DaybriefCore`** — domain value types (`BriefItem`, `Brief`, `Connection`, `Space`, …), shared `JSONValue`/`HTTPTransport`. Pure, `Sendable`.
- **`Secrets`** — Keychain (data-protection) store for tokens, client secrets, the AI key, and the DB key.
- **`Persistence`** — GRDB over SQLite (SQLCipher encryption is available behind a documented build; see `docs/build/grdb-sqlcipher.md`).
- **`ConnectorKit`** — the `Connector` protocol + OAuth (PKCE, loopback listener), the `TokenProvider` seam, fixtures.
- **`GoogleCalendarConnector` / `GmailConnector` / `SlackConnector`** — fetch + normalize only.
- **`LLMKit`** — a model-agnostic `ModelAdapter` (OpenRouter / OpenAI / Anthropic / Gemini / Ollama) with structured-output + validate-and-repair.
- **`BriefRender`** — `Brief` → HTML / Markdown / view model.
- **`Pipeline`** — the orchestrator (concurrent fetch with per-connector timeouts and partial-brief assembly), the editorial synthesizer, the hero-art catalog, and the scheduler.
- **`AppFeature`** — the `@MainActor` app: state, the editorial brief panel, onboarding/settings, scheduling.

### The daily pipeline

```
schedule/wake → fetch (concurrent, per-connector timeout) → normalize
            → synthesize (your model, structured output) → render → persist → in-app brief
```

One dead or slow connector never kills the brief — it degrades to a partial edition with the failure surfaced, never silently dropped.

## Connecting tools (the trust story)

Daybrief routes nothing through a server — you connect each tool with *your own* credentials:

- **Google (Calendar/Gmail)** — you create your own Google "Desktop" OAuth client. Set its consent screen to **In production** to avoid Google's 7-day refresh-token expiry. See [`docs/onboarding/google.md`](docs/onboarding/google.md).
- **Slack** — you create your own **internal** Slack app (don't activate public distribution) and paste its User OAuth token. See [`docs/onboarding/slack.md`](docs/onboarding/slack.md).
- **AI key** — [`docs/onboarding/openrouter.md`](docs/onboarding/openrouter.md).

More onboarding friction, but your credentials never leave your machine.

## Privacy & security

See [`SECURITY.md`](SECURITY.md). In short: tokens and keys live in the macOS Keychain and are never logged; there is no Daybrief server and no third-party token custody; connectors request the minimum OAuth scopes.

## Contributing & license

Contributions are welcome under a CLA — see [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CLA.md`](CLA.md). Daybrief is licensed under **AGPL-3.0-only** (see [`LICENSE`](LICENSE)).
