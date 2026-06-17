# Daybrief — Brief Design Language

> The brief is **editorial, not a dashboard.** It started from Dia browser's morning brief (`docs/design/reference-dia-morning-brief.png`) but is now **its own thing** — see "Our identity" below. This document governs the brief's *structure, voice, and look* — it is binding input for synthesis (Pipeline) and the SwiftUI brief panel (AppFeature).

## Our identity (what makes the brief ours, not a Dia clone)
Four moves give every edition a distinct, self-made character:

1. **Tone-matched hero art.** The hero painting reflects the *day's* character, not a random rotation. The same synthesizer model pass that writes the lede also emits a `mood` (`clear` / `steady` / `busy` / `eventful`); the catalog tags each painting with the moods it suits, and `HeroArtworkCatalog.heroForMood(_:date:)` picks a tone-matched work (deterministic by date within the matching set, with a graceful fall back to the by-date pick). A turbulent Van Gogh for an `eventful` day; a quiet Vermeer for a `clear` one.
2. **Lead story.** The brief leads with the **single most important item of the day**, rendered large as a real headline — `Brief.lead` (a `BriefEntry`), kept *separate* from `sections` so it is never duplicated. In the panel it sits directly under the lede as `BriefLeadView`: a small letterspaced "LEAD" kicker in the edition accent, a heavier serif headline a step larger than a section entry, its context paragraph, the accent CTA badge, and a heavy hairline rule setting it apart from the movements below. Editorial hierarchy, not a flat list. `nil` on a quiet day with nothing to lead with.
3. **Colophon.** A small print-style provenance footer at the foot of the edition — e.g. *"Filed 7:02 AM · 14 signals read, 4 surfaced · Gmail · Calendar"*. **Factual, computed at assembly in `BriefRender` (never by the model):** the filing time, `Brief.signalsRead`, the surfaced count (the lead if present + every section entry), and the contributing `Brief.sources` mapped to display names. A quiet day degrades to *"Filed 7:02 AM · a clear day"*. Set in muted, letterspaced small caps (`BriefColophonView`), replacing the old relative-time footer.
4. **Per-edition accent.** There is **no fixed gold for the brief surface**. Each edition's accent is sampled from its hero painting — a curated `accentHex` per painting on `HeroArtwork` (an ochre from the Vermeer, a stormy blue from a Turner). `DaybriefCore` carries no color type, so the hex travels as a string and the UI converts it via `Color(hex:)`; it threads through the masthead, hero header, lead, action badges, and `.tint`. The app's golden `DaybriefTheme.accent` remains the **fallback** (no hero / no curated hex) and still colors onboarding & settings chrome.

## The feeling
A calm, literary morning periodical written *for one reader*. It reads like a thoughtful editor who has already gone through your inbox, calendar, and messages and is handing you a single, beautifully-set page: here's the shape of your day, here's the one thing worth pushing forward, here's the context so you can just start. Warm, human, a little wry. Never anxious, never a wall of notifications.

## Anatomy (from the reference)
1. **Masthead** — a newspaper-style title named for the weekday: *"The Wednesday Brief"*. Large display serif; the article ("The") in italic, the rest roman, in a warm golden-yellow. This is the edition's identity.
2. **Hero artwork** — a **public-domain fine-art painting** (the reference uses a Pissarro landscape), with a tiny credit line beneath (title · artist · year). Calm, classical, license-safe. Rotates per edition (deterministic by date so a given day is stable).
3. **Vertical rails** — left margin: the dateline (`17 JUN 2026`) rotated 90°; right margin: the generation time (`05:32 AM`) rotated. Like the spine annotations of a periodical.
4. **Lede** — one or two sentences of italic serif editorial prose summarizing the day: *"Nothing on the calendar today or tomorrow. Two full days of uninterrupted heads-down time."* Observational, prose, never bullets.
5. **Action card(s)** — a titled movement (*"Push your work forward"*) containing a prioritized item: a **headline** (*"Draft the revised Cashfeed website copy"*), a paragraph of **context** (who said what, why it matters, what's already known — written as if the assistant has read the threads), and a playful **starburst CTA badge** (*"Let's do it →"*) in the accent yellow.

## Palette & type
- **Background:** warm cream / off-white (`~#FAF7F0`). **Accent:** **per edition**, sampled from the hero painting (see "Our identity" §4); golden yellow (`~#F2C200`) is the fallback and the onboarding/settings accent. **Body:** muted warm grays. Let the painting carry the color.
- **Type:** a classic old-style/transitional **serif** for masthead, lede, and headlines; italics used editorially. On macOS 26 we can use the system serif (`Font.system(.title, design: .serif)`) or bundle a public-domain serif (e.g. EB Garamond / Old Standard TT) for the masthead. Body in a quiet serif or refined sans.
- **Surface:** soft rounded card, gentle shadow; on macOS 26 lean into **Liquid Glass** for the panel chrome. Generous margins — it should feel like a printed page, not a UI.

## Voice rules (for the synthesis prompt)
- Editorial register: calm, concise, literate. Short lede. No corporate filler, no emoji, no exclamation spam.
- **Prioritize ruthlessly:** the brief surfaces *the one or few things that move the day forward*, with context — not an exhaustive list of everything that happened.
- Write context as if you've actually read the source material ("Dennis laid out a clear PAY / MANAGE / OPTIMIZE structure yesterday…"). Reference people and threads by name.
- Honest about quiet days ("Nothing on the calendar…") — emptiness is a feature, not a gap to pad.
- Always **draft-only / suggest** — the CTA invites the user to act, never acts for them.

## Implied data-model extension (additive, back-compatible)
The generic `Brief(sections, entries)` stays, plus optional editorial fields on `DaybriefCore.Brief`. All are optional/defaulted and `Brief`'s custom `init(from:)` uses `decodeIfPresent`, so older persisted payloads still decode:
- `masthead: String` — e.g. "The Wednesday Brief" (weekday-derived).
- `lede: String` — the italic summary prose.
- `lead: BriefEntry?` — the single most important item, the lead story (see "Our identity" §2); separate from `sections`.
- `mood: BriefMood?` — the day's character (`clear`/`steady`/`busy`/`eventful`), read by the synthesizer; drives the tone-matched hero + accent (§1, §4). Forward-compatible decode (unknown → `steady`).
- `hero: HeroArtwork?` — `{ assetName, title, artist, year, sourceURL, accentHex }` referencing a bundled public-domain painting; `accentHex` is the curated per-edition accent (§4).
- `signalsRead: Int` and `sources: [ConnectorID]` — provenance for the colophon (§3), computed at assembly, never by the model.
- `BriefEntry.ctaLabel: String?` — e.g. "Let's do it" (+ existing `url`).

The synthesis JSON schema (Pipeline) targets `masthead`/`lede`/`mood`/`lead`/`sections`; `signalsRead`/`sources`/`hero`/`accent` are assigned at assembly. `BriefRender` projects these into `BriefViewModel` (`lead`, `leadCTALabel`, `colophon`, `accentHex`) and the SwiftUI panel lays them out per the anatomy above.

## Hero artwork sourcing (v0)
Bundle a small curated set (~10–20) of **public-domain** paintings (e.g. Met Open Access / Art Institute of Chicago open access, CC0) as app assets with credit metadata, selected offline & deterministically by date. No network art fetch in v0 (keeps it private + offline). A future version may pull from an open-access museum API.
