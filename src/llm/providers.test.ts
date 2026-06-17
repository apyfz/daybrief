import { describe, it, expect } from "vitest";
import { createAdapter } from "./providers";
import { LlmError } from "./adapter";
import { StubHttpClient } from "@/core/testing";

describe("LLM providers", () => {
  it("OpenRouter sends an OpenAI-compatible request with the key", async () => {
    const http = new StubHttpClient((req) => {
      expect(req.url).toContain("openrouter.ai/api/v1/chat/completions");
      expect(req.headers?.["Authorization"]).toBe("Bearer sk-test");
      const body = JSON.parse(req.body!);
      expect(body.model).toBe("anthropic/claude-sonnet-4-6");
      expect(body.response_format).toEqual({ type: "json_object" });
      return { json: { choices: [{ message: { content: "ok" } }] } };
    });
    const adapter = createAdapter({
      kind: "openrouter",
      model: "anthropic/claude-sonnet-4-6",
      apiKey: "sk-test",
      http,
    });
    const out = await adapter.complete({
      system: "s",
      messages: [{ role: "user", content: "hi" }],
      json: true,
    });
    expect(out).toBe("ok");
  });

  it("Anthropic uses the Messages API shape", async () => {
    const http = new StubHttpClient((req) => {
      expect(req.url).toContain("/v1/messages");
      expect(req.headers?.["x-api-key"]).toBe("sk-ant");
      return { json: { content: [{ text: "hello" }] } };
    });
    const adapter = createAdapter({
      kind: "anthropic",
      model: "claude-opus-4-8",
      apiKey: "sk-ant",
      http,
    });
    expect(
      await adapter.complete({ system: "s", messages: [{ role: "user", content: "x" }] }),
    ).toBe("hello");
  });

  it("Ollama needs no key (local, nothing leaves the box)", async () => {
    const http = new StubHttpClient((req) => {
      expect(req.url).toContain("127.0.0.1:11434");
      return { json: { choices: [{ message: { content: "local" } }] } };
    });
    const adapter = createAdapter({ kind: "ollama", model: "llama3", http });
    expect(
      await adapter.complete({ system: "s", messages: [{ role: "user", content: "x" }] }),
    ).toBe("local");
  });

  it("throws a typed error on HTTP failure", async () => {
    const http = new StubHttpClient(() => ({ status: 401, text: "bad key" }));
    const adapter = createAdapter({
      kind: "openrouter",
      model: "m",
      apiKey: "x",
      http,
    });
    await expect(
      adapter.complete({ system: "s", messages: [{ role: "user", content: "x" }] }),
    ).rejects.toBeInstanceOf(LlmError);
  });

  it("requires a key for cloud providers", () => {
    const http = new StubHttpClient(() => undefined);
    expect(() => createAdapter({ kind: "openai", model: "gpt", http })).toThrow(
      LlmError,
    );
  });
});
