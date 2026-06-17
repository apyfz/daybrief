// Bridge between the web UI and the Rust core. Persistence (SQLite) and secrets
// (OS keychain) live in Rust and are reached via Tauri `invoke`. When running
// outside Tauri (plain `vite dev` in a browser), we fall back to an in-memory +
// localStorage stub so the UI is still developable. Secrets in the fallback are
// deliberately NOT persisted — keys only ever live in the keychain for real.

import type { Connection } from "@/core/types";
import type { AdapterConfig } from "@/llm/adapter";

export interface ModelSettings {
  kind: AdapterConfig["kind"];
  model: string;
  baseUrl?: string;
}

export interface AppSettings {
  model: ModelSettings;
  /** Brief generation time, "HH:MM" local. */
  briefTime: string;
  onboarded: boolean;
}

export interface StoredBrief {
  date: string;
  generatedAt: string;
  html: string;
  json: string; // serialized StructuredBrief
}

const DEFAULT_SETTINGS: AppSettings = {
  model: { kind: "openrouter", model: "anthropic/claude-sonnet-4-6" },
  briefTime: "07:00",
  onboarded: false,
};

function inTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

// --- Settings -------------------------------------------------------------

export async function getSettings(): Promise<AppSettings> {
  if (inTauri()) return invoke<AppSettings>("get_settings");
  const raw = localStorage.getItem("daybrief.settings");
  return raw ? { ...DEFAULT_SETTINGS, ...JSON.parse(raw) } : DEFAULT_SETTINGS;
}

export async function saveSettings(s: AppSettings): Promise<void> {
  if (inTauri()) return invoke("save_settings", { settings: s });
  localStorage.setItem("daybrief.settings", JSON.stringify(s));
}

// --- Connections ----------------------------------------------------------

export async function listConnections(): Promise<Connection[]> {
  if (inTauri()) return invoke<Connection[]>("list_connections");
  const raw = localStorage.getItem("daybrief.connections");
  return raw ? JSON.parse(raw) : [];
}

export async function saveConnection(c: Connection): Promise<void> {
  if (inTauri()) return invoke("save_connection", { connection: c });
  const all = await listConnections();
  const next = [...all.filter((x) => x.id !== c.id), c];
  localStorage.setItem("daybrief.connections", JSON.stringify(next));
}

export async function deleteConnection(id: string): Promise<void> {
  if (inTauri()) return invoke("delete_connection", { id });
  const all = (await listConnections()).filter((x) => x.id !== id);
  localStorage.setItem("daybrief.connections", JSON.stringify(all));
}

// --- Secrets (OS keychain) ------------------------------------------------
// Keys are NEVER stored in localStorage. In the browser fallback they live in a
// module-scoped Map for the session only, mirroring "never written to disk".

const sessionSecrets = new Map<string, string>();

export async function setSecret(key: string, value: string): Promise<void> {
  if (inTauri()) return invoke("set_secret", { key, value });
  sessionSecrets.set(key, value);
}

export async function getSecret(key: string): Promise<string | null> {
  if (inTauri()) return invoke<string | null>("get_secret", { key });
  return sessionSecrets.get(key) ?? null;
}

export async function hasSecret(key: string): Promise<boolean> {
  return (await getSecret(key)) !== null;
}

// --- Briefs ---------------------------------------------------------------

export async function saveBrief(b: StoredBrief): Promise<void> {
  if (inTauri()) return invoke("save_brief", { brief: b });
  localStorage.setItem("daybrief.brief." + b.date, JSON.stringify(b));
  localStorage.setItem("daybrief.brief.latest", b.date);
}

export async function getLatestBrief(): Promise<StoredBrief | null> {
  if (inTauri()) return invoke<StoredBrief | null>("get_latest_brief");
  const date = localStorage.getItem("daybrief.brief.latest");
  if (!date) return null;
  const raw = localStorage.getItem("daybrief.brief." + date);
  return raw ? JSON.parse(raw) : null;
}

export { DEFAULT_SETTINGS };
