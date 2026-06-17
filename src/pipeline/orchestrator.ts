// Core orchestrator (SPEC.md §2, §3). Runs the daily pipeline:
//   connect → (schedule) → fetch → normalize → synthesize → render → deliver
// Resilience is the contract: one dead connector must never kill the brief.

import type {
  AccountCredentials,
  BriefItem,
  Connection,
  HttpClient,
} from "@/core/types";
import type { ModelAdapter } from "@/llm/adapter";
import type { StructuredBrief } from "@/core/brief";
import { getConnector } from "@/connectors/registry";
import { synthesize, isoDate, type SynthesizeOptions } from "./synthesize";
import { renderBriefDocument, renderBriefFragment } from "./render";

/** Resolves credentials for a connection from the OS keychain. */
export type CredentialResolver = (
  connection: Connection,
) => Promise<AccountCredentials>;

export interface RunOptions {
  connections: Connection[];
  adapter: ModelAdapter;
  http: HttpClient;
  resolveCredentials: CredentialResolver;
  /** Filter to a single Space (briefs can be split by space — §5). */
  space?: string;
  /** Calendar lookahead beyond the 24h window, in hours. Default 36h. */
  lookaheadHours?: number;
  synthesis?: SynthesizeOptions;
  now?: Date; // injectable clock for tests
}

/** Per-connector outcome, surfaced so the UI can show partial failures. */
export interface ConnectorRunResult {
  connectorId: string;
  account: string;
  ok: boolean;
  itemCount: number;
  error?: string;
}

export interface BriefResult {
  brief: StructuredBrief;
  html: string; // standalone document (archive/email)
  fragment: string; // in-app fragment
  items: BriefItem[]; // assembled context, retained for chat (§9)
  connectorResults: ConnectorRunResult[];
  generatedAt: string;
}

export async function runPipeline(opts: RunOptions): Promise<BriefResult> {
  const now = opts.now ?? new Date();
  const since = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const until = new Date(
    now.getTime() + (opts.lookaheadHours ?? 36) * 60 * 60 * 1000,
  );

  const active = opts.connections.filter(
    (c) => c.enabled && (!opts.space || c.space === opts.space),
  );

  // --- fetch + normalize, isolated per connection ------------------------
  const allItems: BriefItem[] = [];
  const connectorResults: ConnectorRunResult[] = [];

  // Group connections by connector so each connector fetches its accounts once.
  const byConnector = new Map<string, Connection[]>();
  for (const c of active) {
    const list = byConnector.get(c.connectorId) ?? [];
    list.push(c);
    byConnector.set(c.connectorId, list);
  }

  for (const [connectorId, conns] of byConnector) {
    const connector = getConnector(connectorId);
    if (!connector) {
      for (const c of conns) {
        connectorResults.push({
          connectorId,
          account: c.account.id,
          ok: false,
          itemCount: 0,
          error: `unknown connector "${connectorId}"`,
        });
      }
      continue;
    }

    // Resolve credentials per connection (a failure here is isolated).
    const authorized = [];
    const spaceByAccount = new Map<string, string>();
    for (const c of conns) {
      try {
        const credentials = await opts.resolveCredentials(c);
        authorized.push({ account: c.account, space: c.space, credentials });
        spaceByAccount.set(c.account.id, c.space);
      } catch (err) {
        connectorResults.push({
          connectorId,
          account: c.account.id,
          ok: false,
          itemCount: 0,
          error: `credential error: ${errMsg(err)}`,
        });
      }
    }
    if (authorized.length === 0) continue;

    try {
      const raw = await connector.fetch({
        accounts: authorized,
        since,
        until,
        http: opts.http,
      });
      const normalized = connector.normalize(raw).map((item) => ({
        ...item,
        // Stamp the Space from the owning connection (§5).
        space: item.space || spaceByAccount.get(item.account) || "",
      }));
      allItems.push(...normalized);

      // Per-account item counts for reporting.
      const counts = new Map<string, number>();
      for (const it of normalized)
        counts.set(it.account, (counts.get(it.account) ?? 0) + 1);
      for (const a of authorized) {
        connectorResults.push({
          connectorId,
          account: a.account.id,
          ok: true,
          itemCount: counts.get(a.account.id) ?? 0,
        });
      }
    } catch (err) {
      // Whole-connector failure is contained; the brief still generates.
      for (const a of authorized) {
        connectorResults.push({
          connectorId,
          account: a.account.id,
          ok: false,
          itemCount: 0,
          error: errMsg(err),
        });
      }
    }
  }

  // --- synthesize + render ----------------------------------------------
  const date = opts.synthesis?.date ?? isoDate(now);
  const brief = await synthesize(allItems, opts.adapter, {
    ...opts.synthesis,
    date,
  });
  if (opts.space) brief.space = opts.space;

  return {
    brief,
    html: renderBriefDocument(brief),
    fragment: renderBriefFragment(brief),
    items: allItems,
    connectorResults,
    generatedAt: now.toISOString(),
  };
}

function errMsg(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
