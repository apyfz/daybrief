# The desktop widget

Daybrief ships a native macOS **WidgetKit** desktop widget: a read-only "glance" at
today's brief (masthead, hero, lead story, a few action lines) that you can place on the
desktop or in Notification Center. It is a separate, sandboxed app-extension embedded in
the app bundle (`Daybrief.app/Contents/PlugIns/DaybriefWidget.appex`).

## Architecture: the snapshot bridge

The widget runs in its own **sandboxed** process. It cannot open the SQLCipher database
and cannot read the Keychain — by design. So data reaches it through a shared **App
Group** container, not the database:

```
host app (unsandboxed)                         widget extension (sandboxed)
  AppModel.currentBrief changes                   TimelineProvider
        │                                                 ▲
        ▼                                                 │ reads
  WidgetSnapshotWriter.publish(brief)            WidgetSnapshotStore.load()
        │  writes                                         │
        ▼                                                 │
  ~/Library/Group Containers/<TeamID>.co.daybrief.shared/
        ├── latest-brief.json   (full Brief, Codable)  ──┘
        └── latest-hero.png     (host-downsampled hero)
        │
        └─ WidgetCenter.shared.reloadAllTimelines()  → widget re-renders
```

Key points:

- **Payload is the full `Brief`**, not `BriefViewModel`. The view model has no masthead /
  lede / mood / hero; the panel reads those straight off `Brief`. The widget decodes the
  full `Brief`, then runs `BriefRenderer().viewModel(_:)` on its own side for the lead /
  sections / colophon projection.
- **Hero is rendered host-side.** `NSImage(named:)` resolves against the *main app*
  asset catalog, which the widget bundle does not have. The host downsamples the painting
  (≤1200 px, well under the widget's ~30 MB memory ceiling) and writes a PNG.
- **Refresh is push-driven.** The brief changes ~once a day, so the timeline policy is
  `.never`; the host calls `reloadAllTimelines()` after every brief change (generate,
  dismiss, launch-load). Never reload from a background `AppIntent.perform()`.
- **No secrets ever cross the bridge.** See `SECURITY.md`.

## Module layout

- `DaybriefUI` — a **GRDB-free** SPM library with the palette, type scale, bundled fonts,
  `ActionBadge`, `Color(hex:)`. Shared by `AppFeature` (which re-exports it via
  `Exports.swift`) and the widget. The widget links **only** `DaybriefCore`,
  `BriefRender`, and `DaybriefUI` — never `AppFeature`/`Pipeline`/`Persistence` (which
  pull GRDB into the sandbox).
- `App/Widget/` — the extension target: `DaybriefWidgetBundle.swift` (`@main`
  `WidgetBundle` + provider + snapshot store) and `WidgetBriefViews.swift` (size-specific
  static views). Forces the non-glass rendering — Liquid Glass / `ScrollView` / live
  `openURL` do not work in widgets.
- `AppGroup` (in `DaybriefCore`) — resolves the container from the bundle's
  `AppGroupIdentifier` Info.plist key, so no Team ID is hardcoded.

## Building & signing (the one hard requirement)

A widget that shares an App Group **requires a real Apple Developer Team ID** and proper
signing. The zero-signing dev default (`DEVELOPMENT_TEAM=""`) cannot build a working
widget — `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` and the
extension never registers.

No Team ID is committed. The entitlements and Info.plists use `$(DAYBRIEF_APP_GROUP)` →
`$(TeamIdentifierPrefix)co.daybrief.shared`, which resolves from whatever
`DEVELOPMENT_TEAM` you supply at build time:

```sh
xcodegen generate
xcodebuild -project Daybrief.xcodeproj -scheme Daybrief -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> CODE_SIGN_STYLE=Automatic build
```

Automatic signing + `-allowProvisioningUpdates` registers the App Group capability and
creates the development provisioning profiles for both the app and the extension. A
local Apple **Development**-signed build is enough to run and test the widget on your own
machine; **Developer ID + notarization** is only needed to distribute the app to other
people (so its widget works on their Macs without them having a developer account).

### Verifying

```sh
# Resolved entitlements (expect <TeamID>.co.daybrief.shared on both):
codesign -d --entitlements - --xml "$APP" | plutil -p -
codesign -d --entitlements - --xml "$APP/Contents/PlugIns/DaybriefWidget.appex" | plutil -p -
# Extension registered with the widget system:
pluginkit -mv -p com.apple.widgetkit-extension | grep daybrief
# Appex must NOT link GRDB:
otool -L "$APP/Contents/PlugIns/DaybriefWidget.appex/Contents/MacOS/DaybriefWidget" | grep -i grdb
```

## Deep linking

The whole tile opens the lead story's source (or `daybrief://open` to bring the app
forward — the menu-bar panel can't be opened programmatically, so this surfaces the
main window). Individual action rows on the large size are `Link`s to their `http(s)`
sources and open the browser directly. The `daybrief://` scheme is registered in
`App/Info.plist` (`CFBundleURLTypes`) and handled in `AppDelegate.application(_:open:)`.
