import Foundation
import GRDB

/// Schema migrations for the Daybrief store.
///
/// ## Schema design (v1)
///
/// The connection graph is **normalized** so it can be queried and edited
/// piecewise:
///
/// - `spaces` — one row per ``Space`` (Work / Personal / custom).
/// - `connections` — one row per ``Connection``.
/// - `accounts` — one row per ``Account``, with a foreign key to its
///   `connection`; token material is **not** stored here (only the Keychain
///   `secretRef` coordinates).
///
/// The editorial output is stored more coarsely:
///
/// - `briefs` — one row per ``Brief``. Its `sections` and `connectorErrors`
///   are deeply nested, prioritized, LLM-shaped value trees with no
///   independent query needs of their own, so they are stored as **JSON text
///   columns** (`sections_json`, `connector_errors_json`) rather than being
///   shredded into child tables. This keeps writes atomic and the round-trip
///   lossless, and mirrors the design's "the `Brief` shape doubles as the LLM
///   structured-output schema" intent.
/// - `brief_items` — one row per normalized ``BriefItem``. These *are*
///   normalized into their own table (not folded into the brief JSON) because
///   they are the natural unit for the future FTS5 chat-context index (design
///   §9) and for traceability from `BriefEntry.sourceItemIDs`. v1 does not yet
///   create the FTS table; items carry a nullable `brief_id` so they can be
///   associated with the brief they fed (M1+ wiring), and their list-valued
///   fields (`people`, `urgency_hints`) are stored as JSON text.
/// - `settings` — a typed key/value store (brief fire-time, selected model,
///   `lastBriefDate`, …). One row per key; values are stored as text.
///
/// All identifiers are stored as TEXT (`UUID.uuidString`) for human-readable,
/// stable rows and unambiguous foreign keys.
enum Migrations {
    /// Registers the initial `v1` schema migration. Never edit this after it
    /// has shipped — append new migrations instead.
    static func registerV1(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try db.create(table: "spaces") { t in
                t.primaryKey("id", .text)
                t.column("key", .text).notNull().unique()
                t.column("display_name", .text).notNull()
            }

            try db.create(table: "connections") { t in
                t.primaryKey("id", .text)
                t.column("connector_id", .text).notNull()
                t.column("display_name", .text).notNull()
                t.column("is_enabled", .boolean).notNull()
            }

            try db.create(table: "accounts") { t in
                t.primaryKey("id", .text)
                t.column("connection_id", .text)
                    .notNull()
                    .indexed()
                    .references("connections", onDelete: .cascade)
                t.column("connector_id", .text).notNull()
                t.column("label", .text).notNull()
                t.column("space_key", .text).notNull()
                // Keychain coordinates only — never token material.
                t.column("secret_service", .text).notNull()
                t.column("secret_account", .text).notNull()
            }

            try db.create(table: "briefs") { t in
                t.primaryKey("id", .text)
                t.column("generated_at", .datetime).notNull().indexed()
                t.column("space_filter", .text)
                t.column("sections_json", .text).notNull()
                t.column("connector_errors_json", .text).notNull()
            }

            try db.create(table: "brief_items") { t in
                t.primaryKey("id", .text)
                t.column("brief_id", .text)
                    .indexed()
                    .references("briefs", onDelete: .cascade)
                t.column("source", .text).notNull()
                t.column("account", .text).notNull()
                t.column("space", .text).notNull()
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text)
                t.column("people_json", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("url", .text)
                t.column("urgency_hints_json", .text).notNull()
            }

            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
    }
}
