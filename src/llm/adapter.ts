// Model-agnostic LLM adapter (SPEC.md §6). Single interface, swappable
// backends. BYO key. Keys are resolved from the OS keychain by the caller and
// passed in here — never logged.

import type { HttpClient } from "@/core/types";

export interface Message {
  role: "user" | "assistant";
  content: string;
}

export interface CompleteInput {
  system: string;
  messages: Message[];
  /** Optional: ask the backend for JSON output where supported. */
  json?: boolean;
}

export interface ModelAdapter {
  /** Stable id of the backend, e.g. "openrouter", "anthropic", "ollama". */
  readonly provider: string;
  /** The model this adapter will call, e.g. "anthropic/claude-sonnet-4-6". */
  readonly model: string;
  complete(input: CompleteInput): Promise<string>;
}

/** Provider kinds we know how to construct (SPEC.md §6, §13). */
export type ProviderKind =
  | "openrouter" // recommended one-key default
  | "anthropic"
  | "openai"
  | "google"
  | "ollama"; // local, sends nothing off-box

export interface AdapterConfig {
  kind: ProviderKind;
  /** Model id; provider-specific. */
  model: string;
  /** API key, resolved from the keychain. Not required for local Ollama. */
  apiKey?: string;
  /** Override base URL (e.g. a custom Ollama host or proxy). */
  baseUrl?: string;
  http: HttpClient;
}

export class LlmError extends Error {
  constructor(
    message: string,
    readonly provider: string,
    readonly status?: number,
  ) {
    super(message);
    this.name = "LlmError";
  }
}
