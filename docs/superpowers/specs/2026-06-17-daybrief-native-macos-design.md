# Daybrief — Native macOS Design (v0)

> Status: **approved-pending-review** · Date: 2026-06-17 · Supersedes the Tauri architecture in `~/Desktop/SPEC.md`
> Platform: **macOS only** (Windows/Linux are a later, separately-native effort — explicitly out of scope here).
> Verified provenance for the technical claims below: `docs/research/2026-06-17-native-architecture-research.md` (multi-agent research + adversarial verification, macOS 26 / Swift 6.2 / Xcode 26).
> **Brief look & voice:** `docs/design/brief-design-language.md` — the editorial "Daily Brief" aesthetic (masthead, public-domain fine-art hero, vintage serif, calm lede, prioritized action card), inspired by Dia browser's morning brief. Binding for synthesis (Pipeline) + the brief panel (AppFeature).

---

## 1. What it is

A persistent **menu-bar** macOS app. When you start your day it generates a single editorial brief — priorities, what slipped overnight, today's schedule, what to prep for — assembled from the tools you've connected (v0: Google Calendar, Gmail, Slack). You can later open any item into a chat to dig deeper or draft a reply. Everything runs on your machine; the only thing that leaves is whatever you send to the AI model you chose.

Its edge: neutral across tools, **private by default**, and — in this build — a real native Mac citizen (menu-bar resident, Keychain, launch-at-login, Liquid Glass), not a webview in a wrapper.

---

## 2. Foundational decisions

These are settled and drive everything downstream.

| Decision | Choice | Why |
|---|---|---|
| Platform | Native **Swift 6.2 / SwiftUI**, macOS-only | "As integrated to Macs as possible." The original spec's TypeScript/React/Rust choices were *consequences* of Tauri's cross-platform goal, which we're dropping. Windows/Linux will be their own native stacks later. |
| Min OS | **macOS 26 Tahoe** | Single OS to test/support; Liquid Glass + newest SwiftUI/MenuBarExtra; no availability-gating. |
| Connectors | **Pure Swift**, conforming to a `Connector` protocol | v0's three connectors are HTTP + OAuth + JSON — Swift does this cleanly. Protocol kept abstract enough to back with an out-of-process runner later *if* a contributor community materializes (success-signal-gated, not v0). |
| Persistence | **GRDB.swift 7 over a SQLCipher-encrypted SQLite file**, key in Keychain | The pitch is "your data stays on your machine"; the DB holds mail/message bodies. Real, auditable, key-based at-rest encryption — not just FileVault. |
| Distribution | **Unsandboxed**, Developer ID + hardened runtime, notarized DMG | Google's Desktop OAuth client requires a **loopback HTTP listener**, fragile under sandbox. Sandbox is only mandatory for the App Store. |
| License | **AGPL-3.0-only + contributor CLA** (Apache-style, with relicensing grant) | OSI open source for the connector community + privacy brand; network clause doesn't burden desktop users but deters a closed hosted fork; CLA preserves the right to dual-license a future hosted tier. |

### Assumptions the research overturned (do not regress these)
1. **Gmail "Testing"-status apps lose refresh tokens every 7 days.** Onboarding must guide each user to set their *own* Google OAuth app to **"In production"** (no Google review needed — they're the sole user of their own client). `gmail.metadata` is *also* a restricted scope, so there is no lighter-weight escape; it's `gmail.readonly` + BYO client.
2. **`ASWebAuthenticationSession` cannot receive an `http://` loopback redirect** (only custom schemes). The Google flow needs a real local HTTP listener (`NWListener` on `127.0.0.1:<ephemeral>`); `ASWebAuthenticationSession` is only the in-app browser presenter for providers that *do* use a custom scheme.
3. **Slack only works if the user's app stays "internal"** (single workspace, public distribution never activated) — internal apps keep Tier-3 limits; distributed non-Marketplace apps got throttled to 1 req/min, 15 messages in May 2025. Reading mentions requires **`search.messages`**, which requires a **user token (`xoxp-`)** + `search:read`; bot tokens can't search. The user pastes their User OAuth token from the app config page — no loopback OAuth needed for Slack.
4. **Gmail deep-links (`#all/{id}`) are best-effort**, undocumented and `authuser`-dependent. Include but don't promise.

---

## 3. Module architecture

An Xcode **app target** (`Daybrief`) that owns *only* the menu-bar shell + SwiftUI composition root. All logic lives in local SPM packages wired by one root `Package.swift`. Dependency direction points inward toward `DaybriefCore`.

```
Daybrief (app target)  ── owns MenuBarExtra, lifecycle, composition root
   └─ AppFeature        @Observable AppModel + SwiftUI views   [opts into MainActor]
        ├─ Pipeline      orchestrator (TaskGroup, partial-brief assembly)
        │    ├─ ConnectorKit         Connector protocol, OAuth/Account, fixture harness
        │    │    ├─ GoogleCalendarConnector
        │    │    ├─ GmailConnector
        │    │    └─ SlackConnector
        │    ├─ LLMKit              ModelAdapter protocol + provider registry
        │    └─ BriefRender         structured brief → view model + HTML
        ├─ Persistence    GRDB7 + SQLCipher; exposes DatabaseReader/Writer (DI seam)
        ├─ Secrets        Keychain actor
        └─ DaybriefCore   domain value types + errors (pure, Sendable)
```

**Swift 6.2 isolation rule (verified):** in Xcode 26 the *app target* is MainActor-isolated by default; SPM packages stay `nonisolated` unless a target opts in via `.defaultIsolation(MainActor.self)`. So **only `AppFeature` opts into MainActor**; all logic packages run off the main actor. Every cross-package type crossing a boundary is `Sendable`.

Each package answers: *what it does / how you call it / what it depends on* — and is unit-testable in isolation (connectors against recorded JSON fixtures via `ConnectorKit`'s harness; `Persistence` against an in-memory encrypted DB; `LLMKit` against a stub adapter).

---

## 4. Domain model (`DaybriefCore`)

```swift
public struct BriefItem: Sendable, Codable, Identifiable {
    public let id: UUID
    public let source: String        // connector id: "gcal" | "gmail" | "slack"
    public let account: String       // which connected account
    public let space: String         // "work" | "personal" | custom
    public let type: String          // "email" | "message" | "event" | ...
    public let title: String
    public let body: String?
    public let people: [String]
    public let timestamp: Date
    public let url: URL?             // deep link to the original (best-effort)
    public let urgencyHints: [String] // "unread" | "@mention" | "due-today" | ...
}

public struct Account: Sendable, Codable, Identifiable {
    public let id: UUID
    public let connectorId: String
    public let label: String         // e.g. "alim@crispy.studio"
    public let space: String
    // token material is NOT stored here — referenced by a Keychain handle
    public let secretRef: SecretRef
}

public struct Connection: Sendable, Codable, Identifiable { /* connectorId + [Account] + enabled */ }
public struct Space: Sendable, Codable, Identifiable { /* "work"|"personal"|custom + display + optional schedule */ }

public struct Brief: Sendable, Codable, Identifiable {
    public let id: UUID
    public let generatedAt: Date
    public let spaceFilter: String?            // nil = all spaces
    public let sections: [BriefSection]        // structured, prioritized
    public let connectorErrors: [ConnectorErrorSummary]  // surfaced, never silent
}
public struct BriefSection: Sendable, Codable { /* title + ordered [BriefEntry] */ }
```

The `Brief`/`BriefSection` shape doubles as the **LLM structured-output schema** (§7).

---

## 5. Connector protocol (`ConnectorKit`)

```swift
public protocol Connector: Sendable {
    static var id: String { get }
    static var displayName: String { get }

    var auth: AuthStrategy { get }
    var fetchTimeout: Duration { get }       // per-connector budget for the orchestrator

    func fetch(_ request: FetchRequest) async throws -> [RawItem]   // honors cancellation
    func normalize(_ raw: [RawItem]) -> [BriefItem]
}

public struct FetchRequest: Sendable {
    public let accounts: [Account]
    public let since: Date
    public let until: Date          // window; calendar uses an extended lookahead
}

public enum AuthStrategy: Sendable {
    case loopbackOAuth(OAuthConfig)     // Google: 127.0.0.1 + PKCE + local listener
    case pastedUserToken(TokenSpec)     // Slack: user pastes xoxp- token
    case customSchemeOAuth(OAuthConfig) // reserved for future providers
}
```

- **Multi-account:** one provider → N `Account`s; `fetch` receives all enabled accounts for that connector.
- **Dumb by contract:** connectors fetch + normalize only — never call the LLM, render, or deliver. Keeps future community PRs safe.
- **Transport-readiness caveat (verified):** `Sendable`+`Codable` payloads are *necessary* but not *sufficient* to later swap to an out-of-process/XPC runner without touching call sites — call-site stability depends on the interface *shape*. We therefore keep the interface async-throwing and value-typed from day one, but treat "drop-in XPC later" as a goal, not a guarantee.

---

## 6. Pipeline & orchestrator (`Pipeline`)

```
schedule/wake → fetch (concurrent) → normalize → synthesize → render → persist → deliver(in-app)
```

```swift
enum ConnectorOutcome: Sendable {
    case success([BriefItem])
    case timedOut(connectorId: String)
    case failed(connectorId: String, ConnectorError)
}
```

- Orchestrator runs each enabled connector's `fetch` in `withThrowingTaskGroup`; each child **races the fetch against `connector.fetchTimeout`** and maps *every* result (incl. throws/timeouts) into a non-throwing `ConnectorOutcome`. **One dead/slow connector can never throw out of the group or kill the brief** — we always assemble a partial brief + a surfaced `connectorErrors` list.
- Cancellation is cooperative: `URLSession` async honors it (surfaces `URLError.cancelled`); connectors must not block.
- Retry/backoff: truncated exponential backoff on `429`/`403 userRateLimitExceeded`, bounded in-flight concurrency for fan-out calls (Gmail per-user 250 units/sec — cap `messages.get` at ~5–8 in flight).
- Synthesize: normalized items + system prompt + template → `LLMKit.completeStructured(...)` → `Brief`.
- Persist every brief (encrypted DB) + render an HTML archive copy (M3).

---

## 7. v0 connectors

### 7.1 Google Calendar (`gcal`)
- **Auth:** `loopbackOAuth`, BYO Google Desktop client, PKCE S256, scope `calendar.readonly` (+ `calendar.calendarlist.readonly` to enumerate calendars).
- **Fetch:** `events.list` per selected calendar, `singleEvents=true&orderBy=startTime`, `timeMin`/`timeMax` = today 00:00 → tomorrow 23:59 (RFC3339). Quota: 600 req/min/user — trivial.
- **Normalize:** `type:"event"`, `title`=summary, `people`=attendees, `timestamp`=start, `url`=`htmlLink`, `urgencyHints`=`["scheduled-today"]` when today. Also covers Notion Calendar (a front-end over Google Calendar).

### 7.2 Gmail (`gmail`, multi-account)
- **Auth:** `loopbackOAuth`, **BYO Google Desktop client**, scope `gmail.readonly` (restricted — `gmail.metadata` is *also* restricted, no escape). **Onboarding must drive the user's own app to "In production"** to avoid the 7-day refresh-token death; store + refresh tokens, handle re-consent gracefully if revoked.
- **Fetch:** `messages.list?q=(is:unread OR is:important) newer_than:1d&maxResults=50`, then `messages.get?format=metadata&metadataHeaders=From,Subject,Date` (snippet is returned even in metadata mode — no `format=full`, no body in v0). Cap concurrency ~5–8, backoff on 429.
- **Normalize:** `type:"email"`, `title`=Subject, `people`=From, `body`=snippet, `url`=best-effort `#all/{id}` (don't promise), `urgencyHints` from `is:unread`/`is:important`.

### 7.3 Slack (`slack`, BYO app per workspace)
- **Auth:** `pastedUserToken` — user creates their own **internal** app (distribution never activated), installs to their workspace, pastes the **User OAuth token (`xoxp-`)**. Scopes (minimum): `search:read`, `im:history`, `mpim:history`, `users:read` (+ `groups:history`/`channels:history` only if we read named channels).
- **Fetch:** mentions via `search.messages` (user-token-only); DMs via `conversations.list?types=im,mpim` + `conversations.history` over the 24h window. Internal app ⇒ Tier-3 limits.
- **Normalize:** `type:"message"`, `people`=sender, `urgencyHints`=`["@mention"]`/`["unread"]`, `url`=permalink.
- **Fallback:** if a user mis-configures their app as distributed, detect the Tier-1 throttle and degrade gracefully with a clear "set your app back to internal" message.

---

## 8. LLM adapter (`LLMKit`)

```swift
public protocol ModelAdapter: Sendable {
    func complete(_ input: CompletionInput) async throws -> String
    func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error>
    func completeStructured<T: Decodable & Sendable>(_ input: CompletionInput,
                                                     schema: JSONSchema,
                                                     as: T.Type) async throws -> T
}
public struct CompletionInput: Sendable { public let system: String; public let messages: [ChatMessage] }
```

- **Backends** (each a `Sendable` actor/struct): **OpenRouter (default on-ramp)**, OpenAI, Anthropic, Gemini, **Ollama (local)**. A `ProviderRegistry` maps provider id + user config → adapter.
- **Streaming:** shared SSE reader over `URLSession.bytes(for:).lines` parsing `data:` frames; Ollama is NDJSON (sibling reader).
- **Structured output:** standardize OpenRouter on `response_format: {type:"json_schema", json_schema:{name, strict:true, schema}}` + `provider.require_parameters:true`; **always** run output through a provider-agnostic validate-and-repair parser (passthrough fidelity varies by underlying model). Anthropic uses tool-use; Gemini `responseSchema`; the repair layer is the universal safety net.
- **OpenAI** target = Chat Completions (`/v1/chat/completions`), not the Responses API (correct for a multi-provider adapter).
- **Model IDs resolved at runtime** via each provider's `/models` endpoint — never hard-coded.
- **Config:** synthesis system prompt + render template are **user-editable files** at `~/Library/Application Support/Daybrief/prompts/`, with bundled defaults as fallback. Tune voice/layout without forking.

---

## 9. Persistence (`Persistence`)

- **GRDB.swift 7.11 + SQLCipher.swift (≥4.11)** via SPM. **Known setup task:** SQLCipher-over-SPM still requires a small GRDB fork (uncomment 4 marked lines in its `Package.swift`); no clean trait yet. Apple-Silicon-clean (CommonCrypto backend, no OpenSSL → no extra hardened-runtime exceptions).
- **Key:** 256-bit random generated on first launch, stored in Keychain, applied as a *raw* key (`PRAGMA key = "x'<64-hex>'"`, skipping KDF) inside `Configuration.prepareDatabase`. `DatabaseQueue` (single writer, modest data) + `DatabaseMigrator`.
- **Concurrency:** GRDB 7 is built in Swift 6 language mode; `DatabaseQueue` is `Sendable`; `ValueObservation` integrates with `@Observable` view models.
- **Schema (sketch):** `spaces`, `connections`, `accounts`, `briefs`, `brief_items`, `settings`. Optional **FTS5** virtual table over `brief_items` for chat-context search (M5).
- DB file at `~/Library/Application Support/Daybrief/daybrief.sqlite` (encrypted). Verify ciphertext on disk in tests.

---

## 10. Secrets (`Secrets`)

- All secrets are `kSecClassGenericPassword` items in the **Data-Protection keychain** (`kSecUseDataProtectionKeychain` on every call), accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (a post-wake brief can read tokens with the screen locked; off iCloud/Time-Machine).
- Items: per-account OAuth access+refresh tokens, BYO Google client id/secret, Slack user token, the LLM API key, the SQLCipher DB key.
- Thin Swift **actor** wrapping `SecItem*`, with an upsert helper (add → update on `errSecDuplicateItem`); stable `service`+`account` naming. All secret interpolations marked `.private`/`.sensitive` — never reach `os_log`.
- **M0 integration question to settle empirically:** the Data-Protection keychain on an *unsandboxed* Developer-ID app may require a `keychain-access-groups` entitlement (with a provisioning profile) vs. falling back to the legacy login keychain. Resolve during the shell build before token storage is wired.

---

## 11. Shell & lifecycle (`AppFeature` + app target)

- **`MenuBarExtra` (`.window` style)** hosts the rich, scrollable brief panel. A separate window scene hosts onboarding / OAuth / settings (a popover can't host the web-auth + account flows reliably).
- **Accessory app** via programmatic `NSApplication.shared.setActivationPolicy(.accessory)` at launch (no Dock icon); temporarily promote to `.regular` to front the onboarding/settings window with proper focus, then drop back. (Avoids the static-`LSUIElement` "window won't focus" bug class.)
- **Launch-at-login:** `SMAppService.mainApp.register()/unregister()`; the toggle reads live `.status` (never a stored bool); when `.requiresApproval`, deep-link to System Settings → Login Items.

---

## 12. Scheduling & generate-on-wake (`Pipeline`)

- No daemon, no server. A self-rescheduling wall-clock alarm (`DispatchSourceTimer`) computed from the user's local fire-time fires while the app runs. **Not** `NSBackgroundActivityScheduler` (deliberately imprecise — won't honor 7:00).
- **Catch-up semantics:** on `NSWorkspace.didWakeNotification` *and* on launch, compare a persisted `lastBriefDate` against "today's fire-time has passed" → generate if missed. (Verified: while asleep no app code runs at all; and wake notifications are flaky on some MacBooks, so **launch-time catch-up is the real safety net**.)
- Generation work wrapped in `ProcessInfo.processInfo.beginActivity(.userInitiated)` so App Nap doesn't throttle the timer/network on this accessory app.

---

## 13. Spaces

- Each `Account` carries a `space` tag (default Work/Personal; custom allowed). A Space is just a tag on a connection — every item already carries its account.
- The brief can be filtered or split by Space (privacy: don't blend personal mail into a work brief you might screen-share).
- Per-Space schedules/prompts are a later refinement (data model supports it; UI deferred past v0).

---

## 14. Onboarding flow (native)

1. **Launch** → enter an AI key. Recommend **OpenRouter** (one key, any model); also direct provider keys or a local Ollama endpoint. Stored in Keychain. Prove `complete()` with a tiny round-trip before continuing.
2. **Connect tools as needed** — each connector optional, each walks its own guided auth:
   - *Google (Calendar/Gmail):* guided BYO-client setup — create a Cloud project, enable APIs, create a **Desktop** OAuth client, **set consent screen to "In production"**, then the in-app loopback+PKCE flow.
   - *Slack:* guided **internal** app creation, install to workspace, paste the **User OAuth token**.
3. **Assign each connection to a Space** (Work/Personal/custom).
4. **Set brief time** (+ generate-on-wake fallback is automatic).
5. **Done** — first brief generates.

---

## 15. Security model

- Tokens + keys in the Keychain (Data-Protection keychain), never logged.
- SQLite encrypted at rest (SQLCipher, key in Keychain).
- Minimum OAuth scopes; each scope documented with its reason.
- **No server in the core product** → no third-party token custody.
- Screen-context (v2, out of scope here): RAM-only frames, lossy extraction, hard app/domain exclusions, visible indicator — local-LLM only, never in any hosted tier.

---

## 16. Distribution

Developer ID Application signing + `--options runtime` (hardened runtime) → `xcrun notarytool submit --wait` → `xcrun stapler staple` the `.app` and the enclosing **DMG** (also Developer-ID-signed). Gatekeeper validates offline on first launch. Unsandboxed (see §2).

---

## 17. Licensing & governance

- **AGPL-3.0-only** outbound license.
- **Contributor CLA** (Apache-style ICLA with an explicit relicensing/license-back grant) — **not** a DCO — so the project retains the unilateral right to dual-license a future hosted/commercial tier (AGPL alone can't grant this).
- The opt-in **screen-capture module is a build-flag / product-policy concern, not a license one** — AGPL doesn't force shipping it anywhere, and its copyleft helps guarantee it never silently appears in a third party's closed hosted fork.
- **Decide before the first external PR:** CLA text + signing mechanism (e.g. CLA Assistant), `LICENSE` (AGPL-3.0), `NOTICE`, and the connector-contribution policy (timeboxed maintenance, see spec §15).

---

## 18. Build sequence

This spec covers the **v0 architecture (M0–M3)**. Each milestone is its own spec→plan→build cycle; the first implementation plan targets **M0–M1**.

- **M0 — Shell:** Xcode app + SPM packages skeleton, `MenuBarExtra` accessory app, launch-at-login, `Persistence` (GRDB+SQLCipher) + `Secrets` (Keychain), OpenRouter key entry, `LLMKit` proving `complete()` end-to-end. *Resolve the keychain-entitlement question here.*
- **M1 — First loop:** `GoogleCalendarConnector` → normalize → synthesize → render the brief in-app. One source, full pipeline.
- **M2 — BYO-OAuth connectors:** Gmail (loopback OAuth, "In production" guidance) + Slack (internal app, pasted user token). Formalize `ConnectorKit`.
- **M3 — Spaces + scheduling + delivery:** Work/Personal tagging + filter/split; brief time + generate-on-wake; HTML archive (+ email later).
- **M4+ (future specs):** more connectors (Notion, Figma comments, Typefully, GitHub) · chat/dig-deeper (draft-only) · screen-context (opt-in, local-LLM only, built last).

---

## 19. Testing strategy

- **Connectors:** record real API responses as JSON fixtures; test `fetch` (mocked transport) + `normalize` against them via the `ConnectorKit` harness. No live network in unit tests.
- **Pipeline:** stub connectors that succeed/timeout/throw → assert partial-brief assembly + surfaced errors; assert one dead connector never kills the brief.
- **Persistence:** in-memory encrypted DB; migration round-trips; verify on-disk ciphertext.
- **LLMKit:** stub adapter returning canned JSON; test the validate-and-repair layer against malformed output.
- **Manual/native:** menu-bar render, OAuth loopback round-trips (real BYO clients), launch-at-login status flow, wake/launch catch-up.

---

## 20. Open questions / risks (tracked, not blocking)

1. **Keychain entitlement on unsandboxed Developer-ID** (§10) — settle empirically in M0.
2. **GRDB+SQLCipher SPM fork** (§9) — pin the fork or vendor; document the 4-line patch so the build is reproducible.
3. **Gmail deep-link reliability** (§7.2) — best-effort; consider an RFC822 permalink fallback.
4. **Slack `search.messages` is "legacy"** (no sunset announced as of 2026-06) — monitor; the Real-time Search API also bars distributed apps, so internal-app posture remains correct either way.
5. **Google "In production" friction** — the onboarding's hardest step; invest in clear guided UI + screenshots.

---

## 21. Out of scope (v0)

Notion/Figma/Typefully/GitHub connectors · chat/dig-deeper · email + web-archive delivery beyond the local HTML copy · screen-context module · phone/relay delivery · hosted tier · Windows/Linux.
