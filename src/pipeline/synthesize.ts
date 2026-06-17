// Synthesize step (SPEC.md §3 step 5): normalized items + prompt template →
// chosen model → structured brief. Model-agnostic via ModelAdapter.

import type { BriefItem } from "@/core/types";
import type { ModelAdapter } from "@/llm/adapter";
import { parseStructuredBrief, type StructuredBrief } from "@/core/brief";
import {
  DEFAULT_SYNTHESIS_SYSTEM_PROMPT,
  buildSynthesisUserMessage,
} from "./prompt";

export interface SynthesizeOptions {
  /** Override the default system prompt (config-file editable — §6). */
  systemPrompt?: string;
  /** ISO date (YYYY-MM-DD) the brief is for. Defaults to today. */
  date?: string;
}

export async function synthesize(
  items: BriefItem[],
  adapter: ModelAdapter,
  opts: SynthesizeOptions = {},
): Promise<StructuredBrief> {
  const date = opts.date ?? isoDate(new Date());

  // No items → a valid empty brief; don't burn a model call.
  if (items.length === 0) {
    return {
      date,
      summary: "Nothing pulled from your connected tools for today.",
      sections: [],
    };
  }

  const system = opts.systemPrompt ?? DEFAULT_SYNTHESIS_SYSTEM_PROMPT;
  const userMessage = buildSynthesisUserMessage(items, date);

  const raw = await adapter.complete({
    system,
    messages: [{ role: "user", content: userMessage }],
    json: true,
  });

  return parseStructuredBrief(raw, date);
}

export function isoDate(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function pad(n: number): string {
  return n.toString().padStart(2, "0");
}
