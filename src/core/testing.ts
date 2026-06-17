// Test helpers: a stub HttpClient and a stub ModelAdapter so the pipeline can
// be exercised with no network and no real model.

import type { HttpClient, HttpRequest, HttpResponse } from "./types";
import type { CompleteInput, ModelAdapter } from "@/llm/adapter";

export interface StubResponse {
  status?: number;
  json?: unknown;
  text?: string;
}

/** Routes requests by a matcher → canned response. Records all calls. */
export class StubHttpClient implements HttpClient {
  readonly calls: HttpRequest[] = [];
  constructor(
    private readonly handler: (req: HttpRequest) => StubResponse | undefined,
  ) {}

  async request(req: HttpRequest): Promise<HttpResponse> {
    this.calls.push(req);
    const r = this.handler(req) ?? { status: 404, text: "no stub" };
    const status = r.status ?? 200;
    const text = r.text ?? (r.json !== undefined ? JSON.stringify(r.json) : "");
    return {
      status,
      ok: status >= 200 && status < 300,
      text: async () => text,
      json: async () => (r.json !== undefined ? r.json : JSON.parse(text)),
    };
  }
}

/** Returns a fixed string, or echoes the input via a function. */
export class StubModelAdapter implements ModelAdapter {
  readonly provider = "stub";
  readonly model = "stub-1";
  readonly calls: CompleteInput[] = [];
  constructor(private readonly responder: string | ((i: CompleteInput) => string)) {}

  async complete(input: CompleteInput): Promise<string> {
    this.calls.push(input);
    return typeof this.responder === "function"
      ? this.responder(input)
      : this.responder;
  }
}
