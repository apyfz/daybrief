// Settings (SPEC.md §4 step 4, §6): model/provider, API key, brief time.

import { useState } from "react";
import { saveSettings, setSecret, type AppSettings } from "../bridge";
import { MODEL_KEY_SECRET } from "../generate";
import type { AdapterConfig } from "@/llm/adapter";

const KINDS: { kind: AdapterConfig["kind"]; label: string; needsKey: boolean }[] =
  [
    { kind: "openrouter", label: "OpenRouter", needsKey: true },
    { kind: "anthropic", label: "Anthropic", needsKey: true },
    { kind: "openai", label: "OpenAI", needsKey: true },
    { kind: "google", label: "Google", needsKey: true },
    { kind: "ollama", label: "Ollama (local)", needsKey: false },
  ];

export function SettingsView({
  settings,
  onChange,
}: {
  settings: AppSettings;
  onChange: (s: AppSettings) => void;
}) {
  const [draft, setDraft] = useState<AppSettings>(settings);
  const [key, setKey] = useState("");
  const [saved, setSaved] = useState(false);
  const needsKey = KINDS.find((k) => k.kind === draft.model.kind)?.needsKey;

  async function save() {
    if (key.trim()) await setSecret(MODEL_KEY_SECRET, key.trim());
    await saveSettings(draft);
    onChange(draft);
    setKey("");
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }

  return (
    <div>
      <h1 className="h1">Settings</h1>
      <p className="sub">Model, key, and schedule. Keys live in your keychain.</p>

      <div className="card">
        <div className="field">
          <label>AI provider</label>
          <select
            value={draft.model.kind}
            onChange={(e) =>
              setDraft({
                ...draft,
                model: {
                  ...draft.model,
                  kind: e.target.value as AdapterConfig["kind"],
                },
              })
            }
          >
            {KINDS.map((k) => (
              <option key={k.kind} value={k.kind}>
                {k.label}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Model</label>
          <input
            value={draft.model.model}
            onChange={(e) =>
              setDraft({
                ...draft,
                model: { ...draft.model, model: e.target.value },
              })
            }
          />
        </div>
        {needsKey && (
          <div className="field">
            <label>API key (leave blank to keep current)</label>
            <input
              type="password"
              placeholder="••••••••"
              value={key}
              onChange={(e) => setKey(e.target.value)}
            />
          </div>
        )}
        {draft.model.kind === "ollama" && (
          <div className="field">
            <label>Ollama endpoint (optional)</label>
            <input
              placeholder="http://127.0.0.1:11434/v1"
              value={draft.model.baseUrl ?? ""}
              onChange={(e) =>
                setDraft({
                  ...draft,
                  model: { ...draft.model, baseUrl: e.target.value || undefined },
                })
              }
            />
          </div>
        )}
      </div>

      <div className="card">
        <div className="field">
          <label>Brief time (local)</label>
          <input
            type="time"
            value={draft.briefTime}
            onChange={(e) => setDraft({ ...draft, briefTime: e.target.value })}
          />
          <div className="hint">
            Fires at this time while running; otherwise generates on next wake or
            open.
          </div>
        </div>
      </div>

      <div className="row">
        <button className="primary fixed" onClick={save}>
          Save
        </button>
        {saved && <span className="pill ok">Saved</span>}
      </div>
    </div>
  );
}
