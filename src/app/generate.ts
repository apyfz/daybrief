// Wires the UI/state layer to the pipeline orchestrator: builds the model
// adapter from settings + keychain, resolves each connection's credentials from
// the keychain, runs the pipeline, and persists the resulting brief.

import { runPipeline, type BriefResult } from "@/pipeline/orchestrator";
import { createAdapter } from "@/llm/providers";
import { FetchHttpClient, createTauriHttpClient } from "@/core/http";
import type { AccountCredentials, Connection, HttpClient } from "@/core/types";
import {
  getSecret,
  getSettings,
  listConnections,
  saveBrief,
} from "./bridge";

/** Keychain key holding the model provider API key. */
export const MODEL_KEY_SECRET = "model.apikey";
/** Keychain key holding a connection's credential bundle (JSON). */
export const connectionSecretKey = (connectionId: string) =>
  `conn.${connectionId}`;

async function tauriHttp(): Promise<HttpClient> {
  if (typeof window !== "undefined" && "__TAURI_INTERNALS__" in window) {
    return createTauriHttpClient();
  }
  return new FetchHttpClient();
}

const resolveCredentials = async (
  c: Connection,
): Promise<AccountCredentials> => {
  const raw = await getSecret(connectionSecretKey(c.id));
  if (!raw) throw new Error(`no stored credentials for ${c.account.label}`);
  return JSON.parse(raw) as AccountCredentials;
};

export interface GenerateOptions {
  space?: string;
  now?: Date;
}

export async function generateBrief(
  opts: GenerateOptions = {},
): Promise<BriefResult> {
  const settings = await getSettings();
  const apiKey = (await getSecret(MODEL_KEY_SECRET)) ?? undefined;

  const http = await tauriHttp();
  const adapter = createAdapter({
    kind: settings.model.kind,
    model: settings.model.model,
    baseUrl: settings.model.baseUrl,
    apiKey,
    http,
  });

  const connections = await listConnections();
  const result = await runPipeline({
    connections,
    adapter,
    http,
    resolveCredentials,
    space: opts.space,
    now: opts.now,
  });

  await saveBrief({
    date: result.brief.date,
    generatedAt: result.generatedAt,
    html: result.html,
    json: JSON.stringify(result.brief),
  });

  return result;
}
