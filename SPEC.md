# Daybrief — Build Spec (v0)

> Working codename "Daybrief" — placeholder.
> An open-source, local-first daily brief. A menu-bar desktop app that pulls
> from your tools each morning, writes one prioritized brief, and lets you chat
> with it to dig deeper. Bring your own AI key. Your data stays on your machine.

---

## 1. What it is

A persistent menu-bar desktop app. When you start your day it generates a single
editorial brief — priorities, what slipped overnight, today's schedule, what to
prep for — assembled from the tools you've connected. You can open any item into
a chat to dig deeper or draft a reply. Everything runs on your machine; the only
thing that leaves is whatever you send to the AI model you chose.

Not a chat-first assistant, not tied to any one vendor's ecosystem. Its edge is
being neutral across tools and private by default.

---

## 2. Architecture

**Shape:** Tauri desktop app (Rust core + web UI). Menu-bar resident, launches at
login. Mac first; Windows and Linux from the same codebase.

**Generation model:** while the app is running it can fire on a schedule (e.g.
7am). If the machine was asleep, it generates on first open/wake. No 24/7 server
required. (An optional relay for phone delivery is a v2 add-on, not core.)

**Local-first:** all data and tokens live on-device. Nothing is sent anywhere
except the model API the user picked (and a local model sends nothing off-box).

### Components
- **Core/orchestrator** (Rust) — runs the pipeline, scheduling, retries. One dead
  connector must never kill the brief.
- **Connector plugins** (TypeScript) — one per integration, fixed contract (§7).
- **Normalizer** — connector output → common item shape.
- **LLM adapter** — model-agnostic, BYO key (§6).
- **Renderer** — structured brief → in-app view + HTML (email/web archive).
- **Secrets store** — OS keychain (Tauri keychain plugin).
- **Local DB** — SQLite.
- **Web UI** (React/TS) — onboarding, connections, settings, brief, chat.

### Tech stack
- Shell: **Tauri** (Rust).
- Frontend: **React + TypeScript**.
- Connectors: **TypeScript**, using Tauri's HTTP client (largest contributor pool).
- DB: **SQLite** (local file, encrypted).
- Secrets: OS keychain via Tauri plugin.

---

## 3. The daily pipeline

```
connect → schedule → fetch → normalize → synthesize → render → deliver
```

1. **Connect** — authorize sources once. Multi-account: each authorization is a
   distinct Connection.
2. **Schedule** — fires at the user's time while running; else on wake/open.
3. **Fetch** — each enabled connector pulls a 24h window (+ calendar lookahead).
4. **Normalize** — everything maps to the common BriefItem shape.
5. **Synthesize** — items + prompt template → user's chosen model → structured
   brief (sections, prioritized, clustered by project/person).
6. **Render** — structured output → in-app brief + HTML copy.
7. **Deliver** — in-app (v0); email + web archive; more later.

---

## 4. Onboarding flow

1. **Launch** → enter an AI key. Recommend **OpenRouter** (one key, pick any
   model — Claude/GPT/Gemini/open models). Also accept direct provider keys or a
   local endpoint (Ollama).
2. **Connect tools as needed** — every connector is optional; connect only what
   you use. Each walks its own auth; some require a bring-your-own OAuth app with
   guided steps (Gmail, Slack — see §8).
3. **Assign each connection to a Space** (Work / Personal / custom).
4. **Set brief time + delivery** (in-app to start).
5. **Done** — first brief generates.

---

## 5. Spaces

- Each connected account is tagged with a Space (default Work / Personal; custom
  allowed).
- The brief can be filtered or split by Space.
- Optional per-Space schedule and prompt later (work brief 8am, personal 6pm).
- Data-wise a Space is just a tag on a Connection; every item already carries its
  account. Privacy benefit: don't blend personal mail into a work brief you might
  screen-share.

---

## 6. LLM adapter (bring your own model)

Single interface, swappable backends.

```ts
interface ModelAdapter {
  complete(input: { system: string; messages: Message[] }): Promise<string>;
}
```

- **Default on-ramp: OpenRouter** — one key, any model, simplest setup.
- Also: direct provider keys (Anthropic/OpenAI/Google) and local (Ollama).
- Keys stored in OS keychain, never logged.
- Synthesis prompt + render template are config files — users tune voice/layout
  without forking.
- BYO-model removes inference cost and is a genuine privacy feature.

---

## 7. Connector plugin contract

The extensibility surface. Connectors **fetch and normalize only** — never call
the LLM, render, or deliver. Keeping them dumb makes community PRs safe.

```ts
interface Connector {
  id: string;                 // "gmail", "slack", "gcal", "notion", "figma", "typefully"
  displayName: string;
  authenticate(): OAuthConfig;          // scopes, redirect/loopback handling
  fetch(opts: {
    accounts: Account[];                // one provider can have N accounts
    since: Date;
    until: Date;
  }): Promise<RawItem[]>;
  normalize(raw: RawItem[]): BriefItem[];
}
```

```ts
interface BriefItem {
  source: string;        // connector id
  account: string;       // which connected account
  space: string;         // "work" | "personal" | custom
  type: string;          // "email" | "message" | "event" | "comment" | "draft" ...
  title: string;
  body?: string;
  people?: string[];
  timestamp: Date;
  url?: string;          // deep link to the original
  urgencyHints?: string[]; // "unread" | "@mention" | "due-today" | "scheduled-today"
}
```

---

## 8. Connectors

Connect any subset. Verdicts and gotchas:

- **Google Calendar** — clean. Calendar API, OAuth. Pulls today + tomorrow's
  events. Also covers Notion Calendar (which has no real read API — it's a
  front-end over Google Calendar).
- **Gmail (multiple accounts)** — Gmail API, one OAuth connection per account.
  `gmail.readonly` is a Google *restricted scope*; clean path for an OSS local app
  is **bring-your-own Google OAuth client** (desktop-app flow). Pulls unread /
  important mail in window.
- **Slack** — **bring-your-own Slack app per workspace**. User creates their own
  app and installs it to their workspace; as an internal/custom app it isn't
  subject to the non-Marketplace `conversations.history` rate limits. Pulls
  mentions + DMs in window.
- **Notion** — official REST API, OAuth, reads pages/databases. Pulls recently
  edited/assigned items.
- **Figma comments** — REST API, OAuth. User picks files/projects to watch; pulls
  unresolved comments. (On-brand for a design studio.)
- **Typefully** — API. Pulls today's scheduled posts, pending drafts awaiting
  review, queue status/gaps, and comment threads on drafts. Surfaces "going out
  today" and "needs your review" in the brief.
- **GitHub** — REST/GraphQL API, OAuth. Generous authenticated rate limits, no
  major gotchas. Pulls PRs awaiting your review, your open PRs + their CI/status,
  assigned/mentioned issues, and review requests in window.
- **Dropped: Discord** — reading your own DMs requires automating your user
  account (a self-bot), which violates ToS and risks a ban. Only sanctioned path
  is a bot in a specific server (not DMs). Not a fit.

A recurring pattern: Gmail and Slack push you toward bring-your-own OAuth app.
Embrace it — the user's own credentials, nothing routed through you, and it dodges
rate limits. More onboarding friction, cleaner trust story.

---

## 9. Chat / dig-deeper

- Start a conversation from any brief item or the whole brief.
- Runs on the **already-assembled context** (the normalized items behind today's
  brief), not a fresh pull — fast, and scoped to what the user already surfaced.
- **On-demand fetch:** a follow-up can pull more from a connector when needed,
  rather than the chat holding standing access to all your data.
- BYO model, same as the brief. **Local model = stays on device; cloud model
  (Claude/GPT/etc.) sends that context to the provider — choosable per
  conversation**, surfaced clearly in the UI.
- Inline actions: summarize a thread, draft a reply, pull related items.
- **Drafting only. Sending is always a separate explicit confirm — never
  auto-send.**

---

## 10. Screen-context module (advanced, opt-in)

Off by default. **Self-host + local-LLM only. Never part of any hosted tier.**

- **Capture → extract → delete.** Frame held **in RAM only, never written to
  disk**, processed, then dropped. (No image archive — that's the catastrophic
  version.)
- **Lossy by design.** Extract high-level context ("worked in Figma on the
  Chatbase dashboard ~40 min", "long unread Slack thread from Yasser"), **never
  verbatim field contents.** Don't convert an image archive into a plaintext
  archive of the same secrets.
- **Hard exclusions.** Never capture password managers, banking, Signal/WhatsApp,
  incognito. Default-deny unknown apps/domains.
- **Visible "capturing now" indicator.** Configurable frequency. Never silent.
- The safety comes from the design (ephemeral, lossy, exclusions), not from being
  local. Local is the baseline, not the protection.

---

## 11. Security model

- Tokens encrypted in OS keychain; never logged.
- SQLite DB encrypted at rest.
- Request minimum OAuth scopes; document each and why.
- No server in the core product → no third-party token custody.
- Screen-context (if enabled): RAM-only frames, lossy extraction, exclusion engine.
- NDA note for studio use: even derived notes about confidential client work are a
  record that existed because the tool was watching — exclusion rules covering
  client files matter for self-use.

---

## 12. Licensing

Launch under a **protective license now** — AGPL or a fair-source / BSL-style
license — to keep the productization door open. Relicensing is hard once a
contributor base forms; decide before the first external PR.

---

## 13. Scope

**v0 (ship this):**
- Tauri menu-bar desktop app (macOS), launch at login.
- Local SQLite (encrypted at rest) + OS-keychain secrets.
- AI key entry: **OpenRouter** (recommended one-key default) + direct providers
  + local Ollama, via the model-agnostic LLM adapter.
- Connect-as-needed onboarding (each connector optional, own guided auth).
- Connectors: **Google Calendar, Gmail (multi-account), Slack (BYO app)**.
- Pipeline: fetch → normalize → synthesize → in-app editorial brief (priorities,
  what slipped, today's schedule, what to prep for).
- Spaces: tag connections Work/Personal/custom; filter or split the brief by space.
- Per-user brief schedule + generate-on-wake fallback.
- Minimum OAuth scopes; encrypted token storage.

**v1:**
- More connectors: **Notion, Figma comments, Typefully, GitHub**.
- Connector plugin contract formalized for community contributions.
- Chat / dig-deeper: converse from any item or the whole brief on the
  already-assembled context; on-demand connector fetch; per-conversation model
  choice (local stays on-device / cloud sends context to provider); inline actions
  (summarize, draft, pull related) — **draft-only, sending is a separate confirm**.
- Email delivery + web-archive copy of each brief.
- Customizable synthesis prompt + brief render template.
- Windows + Linux builds from the same codebase.
- Per-space schedules and prompts.

**v2+:**
- Screen-context module — opt-in, off by default, **self-host + local-LLM only,
  never in any hosted tier**: capture → extract → delete (RAM-only frames), lossy
  extraction (no verbatim contents), hard app/domain exclusions, visible
  "capturing now" indicator, configurable frequency.
- Optional phone / cross-device delivery via a small relay.
- Memory built from structured signals + past briefs.
- Hosted tier (same codebase, minus screen capture).

---

## 14. Build order (start here)

- **M0 — Shell:** Tauri app, menu-bar, SQLite, settings, OpenRouter key entry,
  LLM adapter. Prove `complete()` works end to end.
- **M1 — First loop:** Google Calendar connector → normalize → synthesize →
  render brief in-app. One source, full pipeline working.
- **M2 — BYO-OAuth connectors:** Gmail + Slack with guided bring-your-own-app
  setup. Formalize the Connector contract.
- **M3 — Spaces + scheduling + delivery:** Work/Personal tagging, brief time +
  generate-on-wake, email + web archive.
- **M4 — More sources:** Notion, Figma comments, Typefully, GitHub.
- **M5 — Chat:** dig-deeper on the assembled context; inline draft actions
  (draft-only, explicit send).
- **M6 — Screen-context (opt-in):** capture→extract→delete, exclusions, indicator.
  Local-LLM only. Build last, carefully.

---

## 15. Success signals (what to actually watch)

Stars measure that the idea resonates, not that anyone will pay. Track instead:
1. People connecting their **real** Gmail/Slack (trust cleared).
2. Still using it in **week 3** (retention).
3. Non-technical users asking **"is there a hosted version?"** — the only clean
   buy signal.

Timebox connector maintenance from day one so it doesn't become an unpaid second
job before there's a business to justify it.
