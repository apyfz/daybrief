# Daybrief — Brief Design Language

> The brief is **editorial, not a dashboard.** North-star reference: Dia browser's morning brief (`docs/design/reference-dia-morning-brief.png`). This document governs the brief's *structure, voice, and look* — it is binding input for synthesis (Pipeline) and the SwiftUI brief panel (AppFeature).

## The feeling
A calm, literary morning periodical written *for one reader*. It reads like a thoughtful editor who has already gone through your inbox, calendar, and messages and is handing you a single, beautifully-set page: here's the shape of your day, here's the one thing worth pushing forward, here's the context so you can just start. Warm, human, a little wry. Never anxious, never a wall of notifications.

## Anatomy (from the reference)
1. **Masthead** — a newspaper-style title named for the weekday: *"The Wednesday Brief"*. Large display serif; the article ("The") in italic, the rest roman, in a warm golden-yellow. This is the edition's identity.
2. **Hero artwork** — a **public-domain fine-art painting** (the reference uses a Pissarro landscape), with a tiny credit line beneath (title · artist · year). Calm, classical, license-safe. Rotates per edition (deterministic by date so a given day is stable).
3. **Vertical rails** — left margin: the dateline (`17 JUN 2026`) rotated 90°; right margin: the generation time (`05:32 AM`) rotated. Like the spine annotations of a periodical.
4. **Lede** — one or two sentences of italic serif editorial prose summarizing the day: *"Nothing on the calendar today or tomorrow. Two full days of uninterrupted heads-down time."* Observational, prose, never bullets.
5. **Action card(s)** — a titled movement (*"Push your work forward"*) containing a prioritized item: a **headline** (*"Draft the revised Cashfeed website copy"*), a paragraph of **context** (who said what, why it matters, what's already known — written as if the assistant has read the threads), and a playful **starburst CTA badge** (*"Let's do it →"*) in the accent yellow.

## Palette & type
- **Background:** warm cream / off-white (`~#FAF7F0`). **Accent:** golden yellow (`~#F2C200`). **Body:** muted warm grays. Let the painting carry the color.
- **Type:** a classic old-style/transitional **serif** for masthead, lede, and headlines; italics used editorially. On macOS 26 we can use the system serif (`Font.system(.title, design: .serif)`) or bundle a public-domain serif (e.g. EB Garamond / Old Standard TT) for the masthead. Body in a quiet serif or refined sans.
- **Surface:** soft rounded card, gentle shadow; on macOS 26 lean into **Liquid Glass** for the panel chrome. Generous margins — it should feel like a printed page, not a UI.

## Voice rules (for the synthesis prompt)
- Editorial register: calm, concise, literate. Short lede. No corporate filler, no emoji, no exclamation spam.
- **Prioritize ruthlessly:** the brief surfaces *the one or few things that move the day forward*, with context — not an exhaustive list of everything that happened.
- Write context as if you've actually read the source material ("Dennis laid out a clear PAY / MANAGE / OPTIMIZE structure yesterday…"). Reference people and threads by name.
- Honest about quiet days ("Nothing on the calendar…") — emptiness is a feature, not a gap to pad.
- Always **draft-only / suggest** — the CTA invites the user to act, never acts for them.

## Implied data-model extension (additive, applied at start of W2)
The generic `Brief(sections, entries)` stays, plus optional editorial fields on `DaybriefCore.Brief`:
- `masthead: String` — e.g. "The Wednesday Brief" (weekday-derived).
- `lede: String` — the italic summary prose.
- `hero: HeroArtwork?` — `{ assetName, title, artist, year, sourceURL }` referencing a bundled public-domain painting.
- `BriefEntry.ctaLabel: String?` — e.g. "Let's do it" (+ existing `url`).
These are optional/back-compatible, so adding them does not break Layers 0–1. The synthesis JSON schema (Pipeline) targets this shape; `BriefRender` + the SwiftUI panel lay it out per the anatomy above.

## Hero artwork sourcing (v0)
Bundle a small curated set (~10–20) of **public-domain** paintings (e.g. Met Open Access / Art Institute of Chicago open access, CC0) as app assets with credit metadata, selected offline & deterministically by date. No network art fetch in v0 (keeps it private + offline). A future version may pull from an open-access museum API.
