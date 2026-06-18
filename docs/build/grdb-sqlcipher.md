# Enabling SQLCipher for GRDB (Daybrief)

> Status: documented build task (design §9, open question §20.2). The default
> SPM build is **plain GRDB, unencrypted** so it stays green. Switching to an
> encrypted store at rest requires the steps below, because GRDB still has **no
> SPM trait/product** that turns SQLCipher on — you must fork GRDB and uncomment
> four marked lines in its `Package.swift`.

This was web-verified in the architecture research (`docs/research/2026-06-17-native-architecture-research.md`, "GRDB.swift + SQLCipher persistence" dimension) against the live GRDB `master` `Package.swift` and the GRDB README "Encryption" section.

## What our code already does

`DatabaseManager` is written so that *no code change* is needed when SQLCipher is enabled:

- `DatabaseManager.makeConfiguration(encryptionKey:)` applies the raw key only inside a `#if SQLCipher` block (the same define GRDB's fork sets). The `db.usePassphrase(...)` API lives behind `#if SQLITE_HAS_CODEC` in GRDB's `Database+SQLCipher.swift`; it does **not** exist in the default build, so referencing it unconditionally would not compile.
- On the default (non-SQLCipher) build, passing an `encryptionKey` throws `PersistenceError.encryptionUnavailable` rather than silently writing plaintext.
- The key is applied as a **raw** 256-bit key (`PRAGMA key = "x'<64-hex>'"` via `usePassphrase`), so SQLCipher skips PBKDF2 derivation. The key is loaded **inside** `prepareDatabase`, never captured in the `Configuration`.
- We use `DatabaseQueue` (single long-lived connection), which stays available even if the Keychain key later becomes unavailable — unlike `DatabasePool`.

So enabling SQLCipher is purely a *packaging* task: point the build at a SQLCipher-enabled GRDB and define `SQLCipher`.

## Pinned versions (verified)

- **GRDB.swift `7.11.0`** — currently resolved in `Package.resolved`. SQLCipher-over-SPM support landed in `7.10.0` (Feb 2026).
- **`sqlcipher/SQLCipher.swift` `>= 4.11.0`** — the official Zetetic SPM package GRDB's `Package.swift` references by name. `4.11.0` embeds SQLite `3.50.4` (≥ 3.35, so UPSERT/RETURNING are available) and uses Apple's **CommonCrypto** backend on macOS (no OpenSSL → no extra hardened-runtime/notarization exceptions on Apple Silicon).

Pin both. Any GRDB upgrade requires re-applying the fork edits below, so record the exact fork commit.

## Step 1 — Fork GRDB and edit its `Package.swift`

Fork `https://github.com/groue/GRDB.swift` and check out tag `v7.11.0`. In the fork's `Package.swift`, uncomment the **four lines marked with `GRDB+SQLCipher`** and swap the SQLite source target. Verbatim from GRDB's own in-file instructions:

1. Add the SQLCipher package dependency:
   ```swift
   dependencies.append(.package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", from: "4.11.0"))
   ```
2. Define the codec flag for C compilation:
   ```swift
   cSettings.append(.define("SQLITE_HAS_CODEC"))
   ```
3. Define the codec flag for Swift compilation:
   ```swift
   swiftSettings.append(.define("SQLITE_HAS_CODEC"))
   ```
4. Define the `SQLCipher` Swift flag (this is what unlocks `usePassphrase`):
   ```swift
   swiftSettings.append(.define("SQLCipher"))
   ```

Then, in the same `Package.swift`:

- **DELETE** the `GRDBSQLite` library product and its `systemLibrary` target.
- **UNCOMMENT** the `GRDBSQLCipher` target, which depends on `.product(name: "SQLCipher", package: "SQLCipher.swift")`.
- In the **`GRDB` target**: DELETE the `GRDBSQLite` dependency and UNCOMMENT both `.product(name: "SQLCipher", package: "SQLCipher.swift")` and `.target(name: "GRDBSQLCipher")`.

(GRDB's `FTS5` define and `swiftLanguageModes: [.v6]` are untouched by these edits, so full-text search and Swift 6 mode survive.)

## Step 2 — Point Daybrief's `Package.swift` at the fork

In **Daybrief's** root `Package.swift`, replace the upstream GRDB dependency with the fork, pinned to your fork commit:

```swift
// Before:
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),

// After (example — use your fork's URL + the exact commit you pinned):
.package(url: "https://github.com/<your-org>/GRDB.swift.git", revision: "<fork-commit-sha>"),
```

Keep the product name `GRDB` in target dependencies (`.product(name: "GRDB", package: "GRDB.swift")`) — the fork keeps the same product name, so no target wiring changes.

## Step 3 — Define `SQLCipher` when building Daybrief's `Persistence` target

`DatabaseManager` gates the key path on `#if SQLCipher`. With the fork in place, define that flag for the `Persistence` target so the gated branch compiles:

```swift
.target(
    name: "Persistence",
    dependencies: ["DaybriefCore", .product(name: "GRDB", package: "GRDB.swift")],
    swiftSettings: [.define("SQLCipher")]
)
```

> Editing `Package.swift` is normally off-limits for module authors during the
> parallel build phase. This single `swiftSettings` line is the **only** change
> the integrator makes to flip encryption on, and it is recorded here so the
> change is reproducible.

## Step 4 — Provide the key from the Keychain

The `Secrets` module owns the 256-bit DB key (generated via `SecRandomCopyBytes` on first launch, stored in the Data-Protection keychain as 32 raw bytes, accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). At startup the app loads those 32 bytes and passes them as `DatabaseManager(url:encryptionKey:)`. Our `makeConfiguration` hex-encodes them into the `x'<64-hex>'` raw-key literal.

## Step 5 — Verify ciphertext on disk (test)

Because SQLCipher writes a random 16-byte salt into the file header, you **cannot** test for a fixed magic — test for the **absence** of the unencrypted magic instead:

- The first 16 bytes of an encrypted file must **not** be the ASCII string `SQLite format 3\u{0}`.
- Opening the file **without** the key must throw SQLite error 26 (`file is encrypted or is not a database`).

Add this as a `#if SQLCipher`-gated test in `PersistenceTests` once the fork is wired (it cannot run on the default plain build, where there is no encryption to verify).

## Gotchas (from the research dimension)

- **Greenfield only.** Supplying a key does not encrypt an existing plaintext DB (SQLite error 26). Daybrief creates the DB encrypted from day one, so this never applies; do not switch an already-shipped plaintext DB to a key without a `sqlcipher_export` migration.
- **One SQLite in the graph.** The SQLCipher package must be the *only* SQLite. Never also pull in vanilla GRDB or system SQLite anywhere in the dependency graph (linker/runtime symbol conflicts).
- **Re-apply on every GRDB bump.** The fork edits must be re-applied whenever GRDB is upgraded; pin the fork commit and record it alongside the GRDB version.
- **Pin the SQLCipher major.** SQLCipher 3 and 4 on-disk formats differ. Pin the SQLCipher major version so a future bump does not silently break existing user databases (a major change would need `PRAGMA cipher_compatibility` or a migration).
- **String key lifetime.** The `x'<hex>'` raw-key string is not guaranteed to be scrubbed from memory (Swift `String` byte lifetime is uncontrolled). Acceptable for a local single-user app; recorded as a known limitation. For maximum hardening, drop to `usePassphrase(_:)`'s `Data` overload with `resetBytes`.
