// Daybrief core (SPEC.md §2). Menu-bar resident Tauri app: owns the encrypted
// SQLite store, the OS-keychain secrets, the scheduler, and the tray. The web
// layer (React/TS) runs the fetch→normalize→synthesize→render pipeline and calls
// back into these commands for persistence and secrets.

mod db;
mod models;
mod scheduler;
mod secrets;

use std::sync::Arc;

use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, WindowEvent,
};

use db::Db;
use models::{AppSettings, Connection, StoredBrief};

pub struct AppState {
    pub db: Db,
}

// --- Commands: settings ---------------------------------------------------

#[tauri::command]
fn get_settings(state: tauri::State<Arc<AppState>>) -> Result<AppSettings, String> {
    state.db.get_settings().map_err(stringify)
}

#[tauri::command]
fn save_settings(state: tauri::State<Arc<AppState>>, settings: AppSettings) -> Result<(), String> {
    state.db.save_settings(&settings).map_err(stringify)
}

// --- Commands: connections ------------------------------------------------

#[tauri::command]
fn list_connections(state: tauri::State<Arc<AppState>>) -> Result<Vec<Connection>, String> {
    state.db.list_connections().map_err(stringify)
}

#[tauri::command]
fn save_connection(
    state: tauri::State<Arc<AppState>>,
    connection: Connection,
) -> Result<(), String> {
    state.db.save_connection(&connection).map_err(stringify)
}

#[tauri::command]
fn delete_connection(state: tauri::State<Arc<AppState>>, id: String) -> Result<(), String> {
    // Best-effort: also drop the connection's stored credentials.
    let _ = secrets::delete_secret(&format!("conn.{id}"));
    state.db.delete_connection(&id).map_err(stringify)
}

// --- Commands: briefs -----------------------------------------------------

#[tauri::command]
fn save_brief(state: tauri::State<Arc<AppState>>, brief: StoredBrief) -> Result<(), String> {
    state.db.save_brief(&brief).map_err(stringify)
}

#[tauri::command]
fn get_latest_brief(state: tauri::State<Arc<AppState>>) -> Result<Option<StoredBrief>, String> {
    state.db.get_latest_brief().map_err(stringify)
}

// --- Commands: secrets (OS keychain) --------------------------------------

#[tauri::command]
fn set_secret(key: String, value: String) -> Result<(), String> {
    secrets::set_secret(&key, &value).map_err(stringify)
}

#[tauri::command]
fn get_secret(key: String) -> Result<Option<String>, String> {
    secrets::get_secret(&key).map_err(stringify)
}

fn stringify<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .setup(|app| {
            // Open the encrypted DB with a keychain-held key (SPEC.md §11).
            let dir = app.path().app_data_dir().expect("resolve app data dir");
            let db_key = secrets::get_or_create_db_key().map_err(|e| format!("db key: {e}"))?;
            let db = Db::open(dir.join("daybrief.sqlite"), &db_key)
                .map_err(|e| format!("open db: {e}"))?;
            app.manage(Arc::new(AppState { db }));

            build_tray(app.handle())?;
            scheduler::spawn(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            // Menu-bar resident: closing the window hides it instead of quitting.
            if let WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            list_connections,
            save_connection,
            delete_connection,
            save_brief,
            get_latest_brief,
            set_secret,
            get_secret,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Daybrief");
}

fn build_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open Daybrief", true, None::<&str>)?;
    let generate = MenuItem::with_id(app, "generate", "Generate brief now", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &generate, &quit])?;

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .tooltip("Daybrief")
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => show_main(app),
            "generate" => {
                let _ = tauri::Emitter::emit(app, scheduler::GENERATE_EVENT, ());
                show_main(app);
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    Ok(())
}

fn show_main(app: &tauri::AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.set_focus();
    }
}
