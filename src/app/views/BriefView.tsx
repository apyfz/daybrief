// Today's brief (SPEC.md §3 step 6/7: in-app delivery). Shows the latest stored
// brief and a "Generate now" action that runs the full pipeline.

import { useCallback, useEffect, useRef, useState } from "react";
import {
  getLatestBrief,
  getSettings,
  listConnections,
  type StoredBrief,
} from "../bridge";
import { generateBrief } from "../generate";
import { onGenerateRequested, shouldCatchUp } from "../bootstrap";
import type { ConnectorRunResult } from "@/pipeline/orchestrator";

export function BriefView() {
  const [brief, setBrief] = useState<StoredBrief | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<ConnectorRunResult[] | null>(null);
  const busyRef = useRef(false);

  const generate = useCallback(async () => {
    if (busyRef.current) return; // guard against overlapping runs
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      const r = await generateBrief();
      setResults(r.connectorResults);
      setBrief(await getLatestBrief());
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }, []);

  // Load the latest brief; subscribe to the core's generate signal; catch up
  // on wake if the scheduled time passed while the app wasn't running.
  useEffect(() => {
    let unlisten = () => {};
    (async () => {
      const latest = await getLatestBrief();
      setBrief(latest);
      unlisten = await onGenerateRequested(generate);

      const [settings, connections] = await Promise.all([
        getSettings(),
        listConnections(),
      ]);
      if (connections.length > 0 && shouldCatchUp(settings, latest)) {
        generate();
      }
    })();
    return () => unlisten();
  }, [generate]);

  const failures = results?.filter((r) => !r.ok) ?? [];

  return (
    <div>
      <div className="row" style={{ justifyContent: "space-between" }}>
        <div>
          <h1 className="h1">Today's brief</h1>
          <p className="sub">
            {brief
              ? `Generated ${new Date(brief.generatedAt).toLocaleString()}`
              : "No brief yet."}
          </p>
        </div>
        <button className="primary fixed" disabled={busy} onClick={generate}>
          {busy ? "Generating…" : "Generate now"}
        </button>
      </div>

      {error && <div className="banner">Generation failed: {error}</div>}
      {failures.length > 0 && (
        <div className="banner warn">
          Some sources had trouble (the brief still generated):{" "}
          {failures.map((f) => `${f.connectorId} (${f.error})`).join("; ")}
        </div>
      )}

      {brief ? (
        <div className="brief-frame">
          <iframe title="brief" srcDoc={brief.html} />
        </div>
      ) : (
        <div className="empty-state">
          Connect a tool, then generate your first brief.
        </div>
      )}
    </div>
  );
}
