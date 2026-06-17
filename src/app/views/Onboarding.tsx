// Onboarding (SPEC.md §4): enter an AI key (OpenRouter recommended), then land
// in the app to connect tools. Keys go straight to the keychain via setSecret.

import { useState } from "react";
import { getSettings, saveSettings } from "../bridge";
import { MODEL_KEY_SECRET } from "../generate";
import { setSecret } from "../bridge";
import type { AdapterConfig } from "@/llm/adapter";

const PRESETS: {
  kind: AdapterConfig["kind"];
  label: string;
  model: string;
  needsKey: boolean;
  hint: string;
}[] = [
  {
    kind: "openrouter",
    label: "OpenRouter (recommended)",
    model: "anthropic/claude-sonnet-4-6",
    needsKey: true,
    hint: "One key, pick any model — Claude, GPT, Gemini, open models.",
  },
  {
    kind: "anthropic",
    label: "Anthropic (direct)",
    model: "claude-sonnet-4-6",
    needsKey: true,
    hint: "Use your Anthropic API key directly.",
  },
  {
    kind: "openai",
    label: "OpenAI (direct)",
    model: "gpt-4o",
    needsKey: true,
    hint: "Use your OpenAI API key directly.",
  },
  {
    kind: "ollama",
    label: "Ollama (local)",
    model: "llama3.1",
    needsKey: false,
    hint: "Runs on your machine. Nothing leaves the box.",
  },
];

export function Onboarding({ onDone }: { onDone: () => void }) {
  const [presetIdx, setPresetIdx] = useState(0);
  const [model, setModel] = useState(PRESETS[0].model);
  const [key, setKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const preset = PRESETS[presetIdx];

  function choosePreset(i: number) {
    setPresetIdx(i);
    setModel(PRESETS[i].model);
  }

  async function finish() {
    setError(null);
    if (preset.needsKey && !key.trim()) {
      setError("An API key is required for this provider.");
      return;
    }
    setBusy(true);
    try {
      if (key.trim()) await setSecret(MODEL_KEY_SECRET, key.trim());
      const settings = await getSettings();
      await saveSettings({
        ...settings,
        model: { kind: preset.kind, model: model.trim() },
        onboarded: true,
      });
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="main" style={{ margin: "0 auto", paddingTop: 60 }}>
      <h1 className="h1">◓ Welcome to Daybrief</h1>
      <p className="sub">
        One prioritized brief from your tools each morning. Bring your own AI
        key — your data stays on your machine.
      </p>

      <div className="card">
        <div className="field">
          <label>AI provider</label>
          <select
            value={presetIdx}
            onChange={(e) => choosePreset(Number(e.target.value))}
          >
            {PRESETS.map((p, i) => (
              <option key={p.kind} value={i}>
                {p.label}
              </option>
            ))}
          </select>
          <div className="hint">{preset.hint}</div>
        </div>

        <div className="field">
          <label>Model</label>
          <input value={model} onChange={(e) => setModel(e.target.value)} />
        </div>

        {preset.needsKey && (
          <div className="field">
            <label>API key</label>
            <input
              type="password"
              placeholder="sk-…"
              value={key}
              onChange={(e) => setKey(e.target.value)}
            />
            <div className="hint">
              Stored in your OS keychain. Never logged, never sent anywhere
              except the model API you picked.
            </div>
          </div>
        )}

        {error && <div className="banner">{error}</div>}

        <button className="primary" disabled={busy} onClick={finish}>
          {busy ? "Saving…" : "Continue"}
        </button>
      </div>
    </main>
  );
}
