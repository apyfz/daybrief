// Concrete ModelAdapter backends (SPEC.md §6, §13).
//   - OpenRouter: recommended one-key default, OpenAI-compatible API.
//   - Anthropic / OpenAI / Google: direct provider keys.
//   - Ollama: local endpoint, sends nothing off-box.
//
// All backends share the same `complete()` contract so the rest of the app is
// model-agnostic. Keys are passed in and never logged.

import type { HttpClient } from "@/core/types";
import {
  type AdapterConfig,
  type CompleteInput,
  type Message,
  type ModelAdapter,
  type ProviderKind,
  LlmError,
} from "./adapter";

/** OpenAI-compatible chat shape, used by OpenRouter, OpenAI and Ollama. */
function toOpenAiMessages(input: CompleteInput) {
  return [
    { role: "system", content: input.system },
    ...input.messages.map((m: Message) => ({ role: m.role, content: m.content })),
  ];
}

async function readError(res: { status: number; text(): Promise<string> }) {
  let body = "";
  try {
    body = await res.text();
  } catch {
    /* ignore */
  }
  return body.slice(0, 500);
}

// ---------------------------------------------------------------------------
// OpenAI-compatible (OpenRouter, OpenAI, Ollama)
// ---------------------------------------------------------------------------

class OpenAiCompatibleAdapter implements ModelAdapter {
  constructor(
    readonly provider: string,
    readonly model: string,
    private readonly http: HttpClient,
    private readonly baseUrl: string,
    private readonly apiKey: string | undefined,
    private readonly extraHeaders: Record<string, string> = {},
  ) {}

  async complete(input: CompleteInput): Promise<string> {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      ...this.extraHeaders,
    };
    if (this.apiKey) headers["Authorization"] = `Bearer ${this.apiKey}`;

    const res = await this.http.request({
      method: "POST",
      url: `${this.baseUrl}/chat/completions`,
      headers,
      body: JSON.stringify({
        model: this.model,
        messages: toOpenAiMessages(input),
        ...(input.json ? { response_format: { type: "json_object" } } : {}),
      }),
    });

    if (!res.ok) {
      throw new LlmError(
        `${this.provider} request failed: ${await readError(res)}`,
        this.provider,
        res.status,
      );
    }
    const data = (await res.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const content = data.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      throw new LlmError(`${this.provider} returned no content`, this.provider);
    }
    return content;
  }
}

// ---------------------------------------------------------------------------
// Anthropic (Messages API)
// ---------------------------------------------------------------------------

class AnthropicAdapter implements ModelAdapter {
  readonly provider = "anthropic";
  constructor(
    readonly model: string,
    private readonly http: HttpClient,
    private readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}

  async complete(input: CompleteInput): Promise<string> {
    const res = await this.http.request({
      method: "POST",
      url: `${this.baseUrl}/v1/messages`,
      headers: {
        "Content-Type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: 4096,
        system: input.system,
        messages: input.messages.map((m) => ({
          role: m.role,
          content: m.content,
        })),
      }),
    });
    if (!res.ok) {
      throw new LlmError(
        `anthropic request failed: ${await readError(res)}`,
        "anthropic",
        res.status,
      );
    }
    const data = (await res.json()) as { content?: { text?: string }[] };
    const text = data.content?.map((b) => b.text ?? "").join("") ?? "";
    if (!text) throw new LlmError("anthropic returned no content", "anthropic");
    return text;
  }
}

// ---------------------------------------------------------------------------
// Google (Gemini generateContent)
// ---------------------------------------------------------------------------

class GoogleAdapter implements ModelAdapter {
  readonly provider = "google";
  constructor(
    readonly model: string,
    private readonly http: HttpClient,
    private readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}

  async complete(input: CompleteInput): Promise<string> {
    const contents = input.messages.map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    }));
    const res = await this.http.request({
      method: "POST",
      url: `${this.baseUrl}/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: input.system }] },
        contents,
      }),
    });
    if (!res.ok) {
      throw new LlmError(
        `google request failed: ${await readError(res)}`,
        "google",
        res.status,
      );
    }
    const data = (await res.json()) as {
      candidates?: { content?: { parts?: { text?: string }[] } }[];
    };
    const text =
      data.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ??
      "";
    if (!text) throw new LlmError("google returned no content", "google");
    return text;
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

const DEFAULT_BASE_URLS: Record<ProviderKind, string> = {
  openrouter: "https://openrouter.ai/api/v1",
  openai: "https://api.openai.com/v1",
  anthropic: "https://api.anthropic.com",
  google: "https://generativelanguage.googleapis.com",
  ollama: "http://127.0.0.1:11434/v1",
};

/** Construct the right ModelAdapter for a provider config (SPEC.md §6). */
export function createAdapter(config: AdapterConfig): ModelAdapter {
  const baseUrl = config.baseUrl ?? DEFAULT_BASE_URLS[config.kind];
  switch (config.kind) {
    case "openrouter":
      requireKey(config);
      return new OpenAiCompatibleAdapter(
        "openrouter",
        config.model,
        config.http,
        baseUrl,
        config.apiKey,
        {
          // OpenRouter attribution headers (optional but recommended).
          "HTTP-Referer": "https://github.com/apyfz/daybrief",
          "X-Title": "Daybrief",
        },
      );
    case "openai":
      requireKey(config);
      return new OpenAiCompatibleAdapter(
        "openai",
        config.model,
        config.http,
        baseUrl,
        config.apiKey,
      );
    case "ollama":
      // Local: no key required, nothing leaves the box.
      return new OpenAiCompatibleAdapter(
        "ollama",
        config.model,
        config.http,
        baseUrl,
        config.apiKey ?? "ollama",
      );
    case "anthropic":
      requireKey(config);
      return new AnthropicAdapter(
        config.model,
        config.http,
        baseUrl,
        config.apiKey!,
      );
    case "google":
      requireKey(config);
      return new GoogleAdapter(
        config.model,
        config.http,
        baseUrl,
        config.apiKey!,
      );
    default: {
      const _exhaustive: never = config.kind;
      throw new LlmError(`unknown provider ${String(_exhaustive)}`, "unknown");
    }
  }
}

function requireKey(config: AdapterConfig) {
  if (!config.apiKey) {
    throw new LlmError(`${config.kind} requires an API key`, config.kind);
  }
}
