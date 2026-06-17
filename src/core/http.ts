// HttpClient implementations. Connectors and the LLM adapter depend on the
// HttpClient interface (core/types.ts) so the same logic runs inside Tauri
// (via the http plugin, which bypasses webview CORS) and inside unit tests
// (via plain fetch / an injected stub).

import type { HttpClient, HttpRequest, HttpResponse } from "./types";

/** Wraps a `fetch`-like function. Used in tests and as a fallback. */
export class FetchHttpClient implements HttpClient {
  constructor(private readonly fetchImpl: typeof fetch = fetch) {}

  async request(req: HttpRequest): Promise<HttpResponse> {
    const res = await this.fetchImpl(req.url, {
      method: req.method,
      headers: req.headers,
      body: req.body,
    });
    return {
      status: res.status,
      ok: res.ok,
      text: () => res.text(),
      json: () => res.json(),
    };
  }
}

/**
 * Tauri-backed client. Imported lazily so this module stays usable in a plain
 * Node/test context where `@tauri-apps/plugin-http` isn't available.
 */
export async function createTauriHttpClient(): Promise<HttpClient> {
  const { fetch: tauriFetch } = await import("@tauri-apps/plugin-http");
  return new FetchHttpClient(tauriFetch as unknown as typeof fetch);
}
