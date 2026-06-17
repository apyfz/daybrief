// Local SQLite store, encrypted at rest via SQLCipher (SPEC.md §2, §11). Holds
// settings, connections and generated briefs. Tokens never live here — those are
// in the keychain (secrets.rs). The DB key is keychain-held and applied with
// PRAGMA key before any access.

use std::path::PathBuf;
use std::sync::Mutex;

use rusqlite::{params, Connection as SqlConn};

use crate::models::{Account, AppSettings, Connection, StoredBrief};

#[derive(Debug, thiserror::Error)]
pub enum DbError {
    #[error("sqlite error: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("serde error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("{0}")]
    Other(String),
}

pub struct Db {
    conn: Mutex<SqlConn>,
}

impl Db {
    /// Open (or create) the encrypted database at `path`, unlocking with `key`.
    pub fn open(path: PathBuf, key: &str) -> Result<Self, DbError> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let conn = SqlConn::open(path)?;
        // SQLCipher: key must be set before any other statement.
        conn.pragma_update(None, "key", key)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        let db = Db {
            conn: Mutex::new(conn),
        };
        db.migrate()?;
        Ok(db)
    }

    fn migrate(&self) -> Result<(), DbError> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS settings (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS connections (
                id TEXT PRIMARY KEY,
                connector_id TEXT NOT NULL,
                account_id TEXT NOT NULL,
                account_label TEXT NOT NULL,
                space TEXT NOT NULL,
                enabled INTEGER NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS briefs (
                date TEXT PRIMARY KEY,
                generated_at TEXT NOT NULL,
                html TEXT NOT NULL,
                json TEXT NOT NULL
            );",
        )?;
        Ok(())
    }

    // --- Settings ---------------------------------------------------------

    pub fn get_settings(&self) -> Result<AppSettings, DbError> {
        let conn = self.conn.lock().unwrap();
        let json: Option<String> = conn
            .query_row("SELECT json FROM settings WHERE id = 1", [], |r| r.get(0))
            .ok();
        match json {
            Some(j) => Ok(serde_json::from_str(&j)?),
            None => Ok(AppSettings::default()),
        }
    }

    pub fn save_settings(&self, s: &AppSettings) -> Result<(), DbError> {
        let json = serde_json::to_string(s)?;
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO settings (id, json) VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET json = excluded.json",
            params![json],
        )?;
        Ok(())
    }

    // --- Connections ------------------------------------------------------

    pub fn list_connections(&self) -> Result<Vec<Connection>, DbError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, connector_id, account_id, account_label, space, enabled, created_at
             FROM connections ORDER BY created_at",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(Connection {
                id: r.get(0)?,
                connector_id: r.get(1)?,
                account: Account {
                    id: r.get(2)?,
                    label: r.get(3)?,
                },
                space: r.get(4)?,
                enabled: r.get::<_, i64>(5)? != 0,
                created_at: r.get(6)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn save_connection(&self, c: &Connection) -> Result<(), DbError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO connections
                (id, connector_id, account_id, account_label, space, enabled, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(id) DO UPDATE SET
                connector_id = excluded.connector_id,
                account_id = excluded.account_id,
                account_label = excluded.account_label,
                space = excluded.space,
                enabled = excluded.enabled",
            params![
                c.id,
                c.connector_id,
                c.account.id,
                c.account.label,
                c.space,
                c.enabled as i64,
                c.created_at,
            ],
        )?;
        Ok(())
    }

    pub fn delete_connection(&self, id: &str) -> Result<(), DbError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM connections WHERE id = ?1", params![id])?;
        Ok(())
    }

    // --- Briefs -----------------------------------------------------------

    pub fn save_brief(&self, b: &StoredBrief) -> Result<(), DbError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO briefs (date, generated_at, html, json)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(date) DO UPDATE SET
                generated_at = excluded.generated_at,
                html = excluded.html,
                json = excluded.json",
            params![b.date, b.generated_at, b.html, b.json],
        )?;
        Ok(())
    }

    pub fn get_latest_brief(&self) -> Result<Option<StoredBrief>, DbError> {
        let conn = self.conn.lock().unwrap();
        let brief = conn
            .query_row(
                "SELECT date, generated_at, html, json FROM briefs
                 ORDER BY generated_at DESC LIMIT 1",
                [],
                |r| {
                    Ok(StoredBrief {
                        date: r.get(0)?,
                        generated_at: r.get(1)?,
                        html: r.get(2)?,
                        json: r.get(3)?,
                    })
                },
            )
            .ok();
        Ok(brief)
    }
}
