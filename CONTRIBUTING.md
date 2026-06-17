# Contributing to Daybrief

Thank you for your interest in Daybrief — a native macOS menu-bar app that
assembles a single editorial daily brief from the tools you connect (v0: Google
Calendar, Gmail, Slack), running entirely on your own machine.

This guide covers how to build and test the project, how the code is laid out,
the contract every connector plugin must satisfy, and the legal step required
before we can merge your contribution.

Before you start, please also read the engineering conventions in
[`docs/build/CONVENTIONS.md`](docs/build/CONVENTIONS.md). They are the
authoritative rules for concurrency, error handling, logging, and API design,
and they take precedence over anything summarized here.

---

## Requirements

Daybrief targets:

- **macOS 26 (Tahoe)** — the deployment target.
- **Swift 6.2** in **Swift 6 language mode** (strict concurrency, "complete").
- **Xcode 26** and Apple Silicon.

The only third-party dependency is **GRDB**, used in the `Persistence` target.
Everything else uses the standard library, Foundation, and Apple system
frameworks. Please do not add new SPM dependencies; if you believe one is
genuinely required, raise it in an issue first.

---

## Build and test

The project builds two ways. The Swift package builds and tests all of the
logic modules from the command line; the Xcode project produces the actual
`Daybrief.app`.

### Swift package (logic modules + tests)

```sh
swift build          # build every module
swift test           # run the full test suite
```

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`).
There is no XCTest. Tests must be deterministic and must never touch the live
network — connectors are exercised against on-disk JSON fixtures in
`Tests/Fixtures/<connector>/` through an injected mock transport.

### App bundle

The Xcode project is generated from `project.yml`. Open `Daybrief.xcodeproj` in
Xcode 26 and build the `Daybrief` scheme, or build from the command line:

```sh
xcodebuild -project Daybrief.xcodeproj -scheme Daybrief -configuration Debug build
```

### Keep the build green

- Do not break `swift build`, `swift test`, or the `xcodebuild` build.
- Do not edit `Package.swift` unless your change genuinely requires it (for
  example, adding a new module target). The encrypted-storage path is gated
  behind a documented GRDB fork — see
  [`docs/build/grdb-sqlcipher.md`](docs/build/grdb-sqlcipher.md). The default
  build is plain, unencrypted GRDB so it stays green; do not flip that on in a
  contribution.

---

## Module layout

Daybrief is a thin Xcode app target plus local Swift Package Manager modules.
The app target owns only the menu-bar shell and the SwiftUI composition root;
all logic lives in packages, and the dependency direction points inward toward
`DaybriefCore`.

```
Daybrief (app target)  — owns MenuBarExtra, lifecycle, composition root
  └─ AppFeature        — @Observable AppModel + SwiftUI views (the only MainActor module)
       ├─ Pipeline     — orchestrator: concurrent fetch, partial-brief assembly
       │    ├─ ConnectorKit            — Connector protocol, auth/account types, fixture harness
       │    │    ├─ GoogleCalendarConnector
       │    │    ├─ GmailConnector
       │    │    └─ SlackConnector
       │    ├─ LLMKit                  — ModelAdapter protocol + provider registry
       │    └─ BriefRender             — structured brief → view model + HTML
       ├─ Persistence  — GRDB (SQLCipher gated behind a fork); DatabaseReader/Writer seam
       ├─ Secrets      — Keychain actor
       └─ DaybriefCore — pure, Sendable domain value types + errors
```

Key rules that follow from this layout:

- **Only `AppFeature` runs on `@MainActor`.** Every other module is
  `nonisolated` by default. Any type crossing a module boundary or persisted to
  the database must be `Sendable`.
- **Roughly one primary type per file**, named after the type
  (`BriefItem.swift`, `KeychainStore.swift`).
- **One typed error enum per module** (for example `ConnectorError`). No
  `try!`, and no `fatalError`/force-unwrap in non-test code except provably-safe
  cases with a one-line justifying comment.
- **No `print(...)`.** Use `os.Logger`. Secrets, tokens, email addresses, and
  message bodies are always logged with `privacy: .private`, never `.public`.

For the deeper rationale (the Swift 6.2 isolation rule, the `Sendable`/`Codable`
boundary types, networking via the injected `HTTPTransport`), read the spec at
[`docs/superpowers/specs/2026-06-17-daybrief-native-macos-design.md`](docs/superpowers/specs/2026-06-17-daybrief-native-macos-design.md)
and the verified API research at
[`docs/research/2026-06-17-native-architecture-research.md`](docs/research/2026-06-17-native-architecture-research.md).

---

## The connector-plugin contract

Connectors are the most common kind of contribution, so they have an explicit
contract. A connector conforms to the `Connector` protocol in `ConnectorKit`:

```swift
public protocol Connector: Sendable {
    static var id: String { get }
    static var displayName: String { get }

    var auth: AuthStrategy { get }
    var fetchTimeout: Duration { get }       // per-connector budget for the orchestrator

    func fetch(_ request: FetchRequest) async throws -> [RawItem]   // honors cancellation
    func normalize(_ raw: [RawItem]) -> [BriefItem]
}
```

### A connector fetches and normalizes. Nothing else.

This is the load-bearing rule, and it is what keeps community contributions safe
to merge:

- **Fetch** — call the provider's API for the requested accounts and time
  window, and return `RawItem`s. Honor cooperative cancellation (let the
  `URLSession` async APIs throw `URLError.cancelled`; never block a thread).
- **Normalize** — map raw provider payloads to `BriefItem`s. This is pure: no
  network, no I/O, no clock reads.

A connector must **never** do any of the following:

- call the LLM, render a brief, or deliver one;
- read or write the database, the Keychain, or any global state;
- spawn its own scheduling, retries beyond what the contract allows, or
  background work;
- log secrets, tokens, addresses, or message bodies at anything other than
  `.private`.

The orchestrator (`Pipeline`) owns everything else: it runs each enabled
connector's `fetch` concurrently in a task group, races each fetch against the
connector's `fetchTimeout`, and maps **every** outcome — success, timeout, or
throw — into a non-throwing result. One dead or slow connector can never throw
out of the group or kill the brief; the pipeline always assembles a partial
brief plus a surfaced list of connector errors. Keeping connectors "dumb" by
contract is precisely what makes that guarantee hold.

### Authentication strategies

A connector declares how it authenticates via `AuthStrategy`:

- `loopbackOAuth` — for providers that require a `127.0.0.1` loopback redirect
  with PKCE and a bring-your-own client (Google Calendar, Gmail).
- `pastedUserToken` — for providers where the user pastes a token they generate
  themselves (Slack `xoxp-` user token).
- `customSchemeOAuth` — reserved for future providers that support a
  custom-scheme redirect.

Use the minimum scopes the connector needs, and document each scope with its
reason. The user-facing setup for the v0 connectors lives under
[`docs/onboarding/`](docs/onboarding/).

### Testing a connector

Record real API responses as JSON fixtures, place them in
`Tests/Fixtures/<connector>/`, and test both `fetch(_:)` (through a mock
transport) and `normalize(_:)` against them via the `ConnectorKit` harness. No
live network in tests. See the existing connectors and their test targets in
`Package.swift` for the established pattern.

### Connector maintenance is timeboxed

Please understand before contributing a connector: third-party APIs change,
deprecate endpoints, and tighten rate limits. Per the design spec (§15), **the
maintenance of any given connector is timeboxed.** A connector that breaks
against an upstream change and is not repaired within its maintenance window may
be marked unmaintained or removed from the default build. Contributing a
connector is a welcome and valued addition, but it is not an open-ended
commitment from the core project to keep it working forever. If you depend on a
connector, the best way to keep it healthy is to help maintain it.

---

## Pull request workflow

1. Open an issue or discussion for non-trivial changes so we can agree on the
   approach before you invest time.
2. Branch off the current development branch.
3. Keep the change focused; follow the conventions and the module layout above.
4. Add or update tests; make sure `swift build`, `swift test`, and the
   `xcodebuild` build all pass.
5. Use neutral, professional language in commit messages and the PR
   description. Describe the change functionally.

---

## Contributor License Agreement (required)

Before we can merge your contribution, you must sign the project's
**Contributor License Agreement (CLA)** — see [`CLA.md`](CLA.md). This is a
one-time step that applies to all of your future contributions.

The CLA is an individual, Apache-style agreement that includes an explicit
license-back / relicensing grant. We require a CLA (rather than relying on a
Developer Certificate of Origin alone) so that the project retains the right to
relicense the codebase — for example, to offer a future hosted tier under a
different license alongside the open-source AGPL-3.0 release. A DCO certifies
provenance but does not grant the project that relicensing right; the CLA does.
Read [`CLA.md`](CLA.md) for the full terms and the signing mechanism.

By submitting a contribution, you confirm that it is your original work (or that
you have the right to submit it) and that it is provided under the terms of the
CLA.

---

## License

Daybrief is released under **AGPL-3.0-only**. Your contributions are accepted
under that outbound license and under the additional grants in the CLA.
