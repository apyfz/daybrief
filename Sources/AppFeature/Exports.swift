// The editorial presentation layer (palette, type scale, fonts, `ActionBadge`,
// `HeroArtworkView`, `paperSheet`/`editorialCard`, `Color(hex:)`) lives in the
// GRDB-free `DaybriefUI` module so the sandboxed desktop widget can share it.
//
// Re-exporting it here keeps every existing AppFeature view compiling unchanged —
// `DaybriefTheme.accent`, `ActionBadge(...)`, `.paperSheet()` etc. resolve as before
// without adding `import DaybriefUI` to each file — and AppFeature's own consumers
// (the app target, the snapshot tool) continue to see these symbols transitively.
@_exported import DaybriefUI
