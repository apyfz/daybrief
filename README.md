# Daybrief

> Open-source, local-first daily brief. A menu-bar desktop app that pulls from
> your tools each morning, writes one prioritized brief, and lets you chat with
> it to dig deeper. **Bring your own AI key. Your data stays on your machine.**

Daybrief assembles one editorial brief — priorities, what slipped overnight,
today's schedule, what to prep for — from the tools you've connected. Everything
runs on your machine; the only thing that leaves is whatever you send to the AI
model you chose (and a local model sends nothing off-box).

See [`SPEC.md`](./SPEC.md) for the full product spec.

## Architecture

A Tauri app: a **Rust core** (menu-bar resident, scheduling, encrypted storage,
OS-keychain secrets) plus a **React/TypeScript** web layer that runs the daily
pipeline and the UI.

```
connect → schedule → fetch → normalize → synthesize → render → deliver
```

| Layer | Lives in | Responsibility |
|-------|----------|----------------|
| Core / orchestrator | `src-tauri/` (Rust) | tray, scheduling, SQLite (encrypted), keychain |
| Pipeline | `src/pipeline/` (TS) | fetch → normalize → synthesize → render |
| Connectors | `src/connectors/` (TS) | fetch + normalize **only** — never call the LLM |
| LLM adapter | `src/llm/` (TS) | model-agnostic, bring-your-own key |
| UI | `src/app/` (React) | onboarding, connections, settings, brief |

The split is deliberate (SPEC §2): the Rust core owns *when* things happen and
where data rests; the web layer owns *how* the brief is built. Connectors stay
"dumb" (fetch + normalize) so community PRs are safe to accept.

> **macOS screen-context (M6):** when we get there, the macOS-only capture work
> will be a small native **Swift sidecar** process the Tauri app shells out to —
> keeping the cross-platform core and TS-connector model intact.

## Status

Implemented so far (**M0 + M1**, the first full vertical slice):

- ✅ Model-agnostic **LLM adapter** — OpenRouter (default), Anthropic, OpenAI,
  Google, and local Ollama, behind one `complete()` interface.
- ✅ **Google Calendar** connector (fetch + normalize).
- ✅ Resilient **orchestrator** — one dead connector never kills the brief.
- ✅ **Synthesis** (structured JSON brief) + **renderer** (in-app HTML, standalone
  archive document, plain-text).
- ✅ **Spaces** (Work / Personal) tagging + filter/split.
- ✅ React UI — onboarding, connections, brief, settings.
- ✅ Rust core — encrypted SQLite (SQLCipher), OS-keychain secrets, tray,
  autostart, scheduler + generate-on-wake.
- ✅ Unit tests across the pipeline, connectors and LLM adapter.

Next (see SPEC §14 build order): **M2** — Gmail + Slack with bring-your-own
OAuth-app flows and a formalized connector contract.

## Develop

Prereqs: Node 20+, pnpm, Rust toolchain. For the desktop shell you also need the
[Tauri system dependencies](https://tauri.app/start/prerequisites/) (on Linux,
`webkit2gtk`).

```sh
pnpm install
pnpm test         # run the TS unit tests
pnpm typecheck    # tsc --noEmit
pnpm dev          # web UI in a browser (uses an in-memory/localStorage fallback)
pnpm tauri dev    # full desktop app (requires the Tauri system deps)
```

The web layer runs standalone in a browser via `pnpm dev` — secrets and storage
fall back to an in-memory/localStorage stub so you can iterate on the UI and
pipeline without building the Rust shell. Real secrets only ever live in the OS
keychain.

## Adding a connector

See [`docs/CONNECTORS.md`](./docs/CONNECTORS.md). In short: implement the
`Connector` interface (`authenticate` / `fetch` / `normalize`), register it in
`src/connectors/registry.ts`, and add a catalog entry. Connectors must not call
the LLM, render, or deliver.

## Privacy & security

- Tokens and API keys live in the **OS keychain**, never logged.
- The local SQLite DB is **encrypted at rest** (SQLCipher; key held in keychain).
- **No server** in the core product — no third-party token custody.
- Minimum OAuth scopes, each documented.

## License

Intended: **AGPL-3.0-or-later** (a protective license, per SPEC §12). The final
choice (AGPL vs. a fair-source / BSL-style license) is to be locked in before the
first external contribution — see [`LICENSE.md`](./LICENSE.md).
