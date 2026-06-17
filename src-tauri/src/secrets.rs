// OS keychain access (SPEC.md §11: tokens encrypted in OS keychain, never
// logged). All secrets — model API keys, per-connection credential bundles, and
// the SQLite encryption key — go through here. Values are never logged.

use keyring::Entry;

const SERVICE: &str = "co.daybrief.app";

#[derive(Debug, thiserror::Error)]
pub enum SecretError {
    #[error("keychain error: {0}")]
    Keyring(#[from] keyring::Error),
}

fn entry(key: &str) -> Result<Entry, SecretError> {
    Ok(Entry::new(SERVICE, key)?)
}

pub fn set_secret(key: &str, value: &str) -> Result<(), SecretError> {
    entry(key)?.set_password(value)?;
    Ok(())
}

pub fn get_secret(key: &str) -> Result<Option<String>, SecretError> {
    match entry(key)?.get_password() {
        Ok(v) => Ok(Some(v)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(SecretError::Keyring(e)),
    }
}

pub fn delete_secret(key: &str) -> Result<(), SecretError> {
    match entry(key)?.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(SecretError::Keyring(e)),
    }
}

/// The SQLite (SQLCipher) encryption key. Generated once and stored in the
/// keychain; the DB is unreadable without it (SPEC.md §11).
pub fn get_or_create_db_key() -> Result<String, SecretError> {
    const DB_KEY: &str = "db-encryption-key";
    if let Some(existing) = get_secret(DB_KEY)? {
        return Ok(existing);
    }
    use rand::RngCore;
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let hex = bytes.iter().map(|b| format!("{b:02x}")).collect::<String>();
    set_secret(DB_KEY, &hex)?;
    Ok(hex)
}
