// Bridges the Rust scheduler/tray to the web pipeline. The core decides *when*
// to generate (timer or tray click → "daybrief://generate" event); the web layer
// decides *how* (runs the TS pipeline). Also implements generate-on-wake: if the
// machine was asleep at the scheduled time, catch up on launch (SPEC.md §2, §3).

import type { AppSettings, StoredBrief } from "./bridge";
import { isoDate } from "@/pipeline/synthesize";

export const GENERATE_EVENT = "daybrief://generate";

function inTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/** Subscribe to the core's generate signal. Returns an unsubscribe function. */
export async function onGenerateRequested(
  handler: () => void,
): Promise<() => void> {
  if (!inTauri()) return () => {};
  const { listen } = await import("@tauri-apps/api/event");
  const unlisten = await listen(GENERATE_EVENT, () => handler());
  return unlisten;
}

/**
 * Generate-on-wake: true when today's brief is missing and the scheduled time
 * has already passed (the timer never fired because the app wasn't running).
 */
export function shouldCatchUp(
  settings: AppSettings,
  latest: StoredBrief | null,
  now = new Date(),
): boolean {
  if (!settings.onboarded) return false;
  const today = isoDate(now);
  if (latest?.date === today) return false; // already have today's

  const [h, m] = settings.briefTime.split(":").map((x) => parseInt(x, 10));
  if (Number.isNaN(h) || Number.isNaN(m)) return false;
  const scheduled = new Date(now);
  scheduled.setHours(h, m, 0, 0);
  return now.getTime() >= scheduled.getTime();
}
