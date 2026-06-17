# Writing a connector

A connector is the only extensibility surface in Daybrief. Connectors **fetch and
normalize only** — they never call the LLM, render, or deliver. Keeping them dumb
is what makes community contributions safe to accept (SPEC §7).

## The contract

Implement the `Connector` interface from [`src/core/types.ts`](../src/core/types.ts):

```ts
interface Connector {
  id: string;            // "gcal", "gmail", "slack", ...
  displayName: string;
  authenticate(): OAuthConfig;            // scopes, redirect handling
  fetch(opts: FetchOptions): Promise<RawItem[]>;
  normalize(raw: RawItem[]): BriefItem[];
}
```

### `authenticate()`

Return the OAuth shape: minimum scopes (document each — SPEC §11), redirect
handling (`loopback` for desktop, or a custom `scheme`), and whether the provider
requires a **bring-your-own OAuth app** (`bringYourOwnApp: true` for Gmail and
Slack — SPEC §8). Provide `setupSteps` when BYO-app is required.

### `fetch(opts)`

Pull a window of raw items for each authorized account. Rules:

- **Isolate per-account failures.** One dead account/connector must never kill
  the brief (SPEC §2). Wrap per-account work in try/catch and return what you can.
- Use `opts.http` (the injected `HttpClient`) — never `fetch` directly. This is
  what lets the same code run inside Tauri (CORS-free) and in unit tests.
- Honor `opts.since` / `opts.until`.

### `normalize(raw)`

Map provider payloads to `BriefItem[]`. Leave `space` as `""` — the orchestrator
stamps it from the owning connection. Populate `urgencyHints` where you can
(`"unread"`, `"@mention"`, `"due-today"`, `"scheduled-today"`).

## Register it

1. Add your connector to [`src/connectors/registry.ts`](../src/connectors/registry.ts).
2. Add a UI entry to [`src/app/catalog.ts`](../src/app/catalog.ts).
3. Write tests modelled on [`src/connectors/gcal.test.ts`](../src/connectors/gcal.test.ts):
   exercise `normalize` directly and `fetch` with a `StubHttpClient`.

## Example

[`src/connectors/gcal.ts`](../src/connectors/gcal.ts) is the reference
implementation: read-only scope, loopback redirect, per-account fetch isolation,
and a `normalize` that drops cancelled events and excludes the user from the
attendee list.
