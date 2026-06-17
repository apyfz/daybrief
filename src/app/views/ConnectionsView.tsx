// Connections (SPEC.md §4 step 2-3, §5). Connect-as-needed: each connector is
// optional and tagged with a Space. Real OAuth (loopback / BYO-app) lands in M2;
// this screen handles assignment, listing, and credential storage. For now,
// connecting captures credentials directly (paste flow) and stores them in the
// keychain — the OAuth dance will populate the same credential bundle.

import { useEffect, useState } from "react";
import {
  deleteConnection,
  listConnections,
  saveConnection,
  setSecret,
} from "../bridge";
import { connectionSecretKey } from "../generate";
import { CONNECTOR_CATALOG, type ConnectorCatalogEntry } from "../catalog";
import { DEFAULT_SPACES } from "@/core/types";
import type { AccountCredentials, Connection } from "@/core/types";

export function ConnectionsView() {
  const [connections, setConnections] = useState<Connection[]>([]);
  const [adding, setAdding] = useState<ConnectorCatalogEntry | null>(null);

  async function refresh() {
    setConnections(await listConnections());
  }
  useEffect(() => {
    refresh();
  }, []);

  async function remove(c: Connection) {
    await deleteConnection(c.id);
    await refresh();
  }

  return (
    <div>
      <h1 className="h1">Connections</h1>
      <p className="sub">
        Connect only what you use. Each account is tagged with a Space so you can
        split or filter the brief.
      </p>

      {connections.length > 0 && (
        <div className="card">
          <div className="connlist">
            {connections.map((c) => {
              const cat = CONNECTOR_CATALOG.find((x) => x.id === c.connectorId);
              return (
                <div className="connrow" key={c.id}>
                  <span style={{ fontSize: 20 }}>{cat?.icon ?? "🔌"}</span>
                  <div className="meta">
                    <div className="title">
                      {cat?.name ?? c.connectorId}{" "}
                      <span className={`pill ${c.space}`}>{c.space}</span>
                    </div>
                    <div className="desc">{c.account.label}</div>
                  </div>
                  <button className="danger fixed" onClick={() => remove(c)}>
                    Remove
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="card">
        <div className="connlist">
          {CONNECTOR_CATALOG.map((cat) => (
            <div className="connrow" key={cat.id}>
              <span style={{ fontSize: 20 }}>{cat.icon}</span>
              <div className="meta">
                <div className="title">
                  {cat.name}{" "}
                  {cat.status === "planned" && (
                    <span className="pill">soon</span>
                  )}
                  {cat.bringYourOwnApp && (
                    <span className="pill">bring-your-own app</span>
                  )}
                </div>
                <div className="desc">{cat.blurb}</div>
              </div>
              <button
                className="fixed"
                disabled={cat.status !== "available"}
                onClick={() => setAdding(cat)}
              >
                Connect
              </button>
            </div>
          ))}
        </div>
      </div>

      {adding && (
        <AddConnectionModal
          entry={adding}
          onClose={() => setAdding(null)}
          onSaved={async () => {
            setAdding(null);
            await refresh();
          }}
        />
      )}
    </div>
  );
}

function AddConnectionModal({
  entry,
  onClose,
  onSaved,
}: {
  entry: ConnectorCatalogEntry;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [space, setSpace] = useState(DEFAULT_SPACES[0].id);
  const [label, setLabel] = useState("");
  const [token, setToken] = useState("");
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    try {
      const id = crypto.randomUUID();
      const account = { id: label.trim() || id, label: label.trim() || entry.name };
      const connection: Connection = {
        id,
        connectorId: entry.id,
        account,
        space,
        enabled: true,
        createdAt: new Date().toISOString(),
      };
      const creds: AccountCredentials = { accessToken: token.trim() };
      await setSecret(connectionSecretKey(id), JSON.stringify(creds));
      await saveConnection(connection);
      onSaved();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,.5)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
      onClick={onClose}
    >
      <div
        className="card"
        style={{ width: 460, margin: 0 }}
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="h1" style={{ fontSize: 16 }}>
          Connect {entry.name}
        </h2>

        {entry.setupSteps && (
          <ol className="steps">
            {entry.setupSteps.map((s, i) => (
              <li key={i}>{s}</li>
            ))}
          </ol>
        )}

        <div className="field">
          <label>Account label</label>
          <input
            placeholder="you@example.com"
            value={label}
            onChange={(e) => setLabel(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Space</label>
          <select value={space} onChange={(e) => setSpace(e.target.value)}>
            {DEFAULT_SPACES.map((s) => (
              <option key={s.id} value={s.id}>
                {s.label}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Access token</label>
          <input
            type="password"
            placeholder="OAuth access token"
            value={token}
            onChange={(e) => setToken(e.target.value)}
          />
          <div className="hint">
            Stored in your OS keychain. Full OAuth sign-in lands in M2; for now
            paste a token to wire the connection.
          </div>
        </div>

        <div className="row">
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" disabled={busy || !token.trim()} onClick={save}>
            {busy ? "Saving…" : "Save connection"}
          </button>
        </div>
      </div>
    </div>
  );
}
