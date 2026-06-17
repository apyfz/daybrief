# Icons

These are placeholder solid-color PNGs so dev builds have a window/tray icon.

Before shipping, replace them with the real artwork by running:

```sh
pnpm tauri icon path/to/daybrief-logo.png
```

That regenerates every platform target (`.icns`, `.ico`, and the PNG set) from a
single 1024×1024 source and rewrites the references in `tauri.conf.json`.
