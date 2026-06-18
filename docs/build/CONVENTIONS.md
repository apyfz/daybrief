# Daybrief — Engineering Conventions (read before writing any code)

Target: **macOS 26**, **Swift 6.2**, **Swift 6 language mode (strict concurrency)**, Xcode 26. Apple Silicon.

## Sources of truth
- Design: `docs/superpowers/specs/2026-06-17-daybrief-native-macos-design.md`
- Verified API/framework specifics (Gmail/Slack/OAuth/GRDB/LLM): `docs/research/2026-06-17-native-architecture-research.md`

If those two conflict with your memory of an API, **trust the docs** — they were web-verified in 2026.

## Dependencies
- The ONLY third-party dependency is **GRDB** (in the `Persistence` target). Everything else uses the standard library, Foundation, and system frameworks (`Security`, `Network`, `AuthenticationServices`, `ServiceManagement`, `AppKit`/`SwiftUI` in `AppFeature` only).
- Do **not** add new SPM dependencies. If you think you need one, note it in `openIssues` instead.

## Concurrency
- All public types that cross a module boundary or are persisted are `Sendable`.
- Use `async`/`await` and structured concurrency. Use `actor` for shared mutable state (Keychain store, registries, token caches).
- Never block a thread. Honor cooperative cancellation (check `Task.isCancelled` / let `URLSession` async throw `URLError.cancelled`).
- Library code is **nonisolated** by default. Only `AppFeature` runs on `@MainActor` (its `AppModel` and SwiftUI views).

## Errors & safety
- One typed error enum per module (e.g. `enum ConnectorError: Error`). No `try!`. No `fatalError`/force-unwrap in non-test code except provably-safe cases with a one-line comment justifying it.
- No `print(...)`. Use `os.Logger`. **Secrets, tokens, emails, and message bodies are always logged with `privacy: .private`** (never `.public`).

## API & files
- Public API is minimal and documented with `///`. Internal helpers stay `internal`/`private`.
- Roughly one primary type per file; name the file after the type (`BriefItem.swift`, `KeychainStore.swift`).
- Value types crossing boundaries: `Sendable`, `Codable`, `Equatable` (and `Identifiable` when they have ids).

## Networking
- Use `URLSession` async APIs. Inject an `HTTPTransport` protocol (from `ConnectorKit`/`LLMKit`) so fetch logic is unit-testable without the network.

## Testing (Swift Testing)
- `import Testing`; `@Test`, `#expect`, `#require`. No XCTest.
- Connectors: test `normalize(_:)` and `fetch(_:)` against on-disk JSON fixtures in `Tests/Fixtures/<connector>/` via a mock transport. **No live network in tests.**
- Pipeline: test partial-brief assembly with stub connectors that succeed / time out / throw.
- Keep tests deterministic — inject clocks/dates, never read wall-clock in assertions.

## Build discipline
- If your task says you are in a **parallel write phase, do NOT run `swift build`** (concurrent builds race on `.build`). Write code; an integrator builds afterward.
- If you are an integrator/sole agent, you may run `swift build` and `swift test`.

## macOS specifics (verified — see research)
- App is **menu-bar accessory** (`setActivationPolicy(.accessory)`), unsandboxed (Developer ID), launch-at-login via `SMAppService.mainApp`.
- Google OAuth = loopback `127.0.0.1` listener + PKCE (`ASWebAuthenticationSession` can't catch http loopback). Slack = pasted `xoxp-` user token (no OAuth dance).
- Persistence is GRDB; SQLCipher encryption is gated behind a documented fork (`docs/build/grdb-sqlcipher.md`) — implement the key-application path but default to unencrypted so the default SPM build stays green, marked `// TODO(SQLCipher)`.
