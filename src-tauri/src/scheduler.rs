// Scheduling (SPEC.md §2, §3 step 2). While the app is running, a lightweight
// loop fires at the user's configured brief time. There's no 24/7 server: if the
// machine was asleep at the scheduled time, the frontend triggers a catch-up
// generation on launch/wake (see App bootstrap). The loop only *signals* — it
// emits an event the web layer listens for and runs the TS pipeline. The core
// stays responsible for *when*; the web layer for *how* (SPEC.md §2 split).

use std::sync::Arc;
use std::thread;
use std::time::Duration;

use chrono::{Local, Timelike};
use tauri::{AppHandle, Emitter, Manager};

use crate::AppState;

/// Event name the frontend subscribes to in order to run the pipeline.
pub const GENERATE_EVENT: &str = "daybrief://generate";

/// Spawn the background scheduler. Checks once a minute whether the local time
/// has reached the configured brief time, and fires at most once per day.
pub fn spawn(app: AppHandle) {
    thread::spawn(move || {
        let mut last_fired_day: Option<u32> = None;
        loop {
            thread::sleep(Duration::from_secs(60));

            let state = app.state::<Arc<AppState>>();
            let settings = match state.db.get_settings() {
                Ok(s) => s,
                Err(_) => continue,
            };
            if !settings.onboarded {
                continue;
            }

            let now = Local::now();
            let Some((h, m)) = parse_hhmm(&settings.brief_time) else {
                continue;
            };

            let today = now.ordinal();
            let already_today = last_fired_day == Some(today);
            let reached = now.hour() > h || (now.hour() == h && now.minute() >= m);

            if reached && !already_today {
                last_fired_day = Some(today);
                let _ = app.emit(GENERATE_EVENT, ());
            }

            // Reset the daily guard once we roll past midnight into a new day.
            if last_fired_day.is_some() && !reached && now.hour() < h {
                // new day, before the fire time — allow a future fire
                if last_fired_day != Some(today) {
                    last_fired_day = None;
                }
            }
        }
    });
}

fn parse_hhmm(s: &str) -> Option<(u32, u32)> {
    let (h, m) = s.split_once(':')?;
    Some((h.trim().parse().ok()?, m.trim().parse().ok()?))
}
