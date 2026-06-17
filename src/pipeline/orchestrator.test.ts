import { describe, it, expect } from "vitest";
import { runPipeline } from "./orchestrator";
import { registerConnector, getConnector } from "@/connectors/registry";
import { StubHttpClient, StubModelAdapter } from "@/core/testing";
import type { Connection, Connector } from "@/core/types";

// A connector that always throws, to prove resilience.
const explodingConnector: Connector = {
  id: "exploder",
  displayName: "Exploder",
  authenticate: () => ({
    authUrl: "",
    tokenUrl: "",
    scopes: [],
    redirect: { kind: "loopback" },
  }),
  fetch: async () => {
    throw new Error("kaboom");
  },
  normalize: () => [],
};

// A trivial connector that yields one item.
const fakeMail: Connector = {
  id: "fakemail",
  displayName: "Fake Mail",
  authenticate: () => ({
    authUrl: "",
    tokenUrl: "",
    scopes: [],
    redirect: { kind: "loopback" },
  }),
  fetch: async (opts) =>
    opts.accounts.map((a) => ({
      source: "fakemail",
      account: a.account.id,
      raw: { subject: "Invoice overdue" },
    })),
  normalize: (raw) =>
    raw.map((r) => ({
      source: "fakemail",
      account: r.account,
      space: "",
      type: "email",
      title: (r.raw as { subject: string }).subject,
      timestamp: new Date("2026-06-17T08:00:00Z"),
      urgencyHints: ["unread"],
    })),
};

registerConnector(explodingConnector);
registerConnector(fakeMail);

function conn(id: string, connectorId: string, space = "work"): Connection {
  return {
    id,
    connectorId,
    account: { id: `${connectorId}-acct`, label: "acct" },
    space,
    enabled: true,
    createdAt: "2026-06-17T00:00:00Z",
  };
}

const briefJson = JSON.stringify({
  date: "2026-06-17",
  summary: "One thing needs you.",
  sections: [
    {
      kind: "priorities",
      title: "Priorities",
      entries: [{ headline: "Pay the overdue invoice", source: "fakemail", priority: 3 }],
    },
  ],
});

describe("runPipeline", () => {
  const base = {
    http: new StubHttpClient(() => undefined),
    resolveCredentials: async () => ({ accessToken: "tok" }),
    now: new Date("2026-06-17T07:00:00Z"),
  };

  it("survives a dead connector and still produces a brief", async () => {
    const adapter = new StubModelAdapter(briefJson);
    const result = await runPipeline({
      ...base,
      adapter,
      connections: [conn("c1", "exploder"), conn("c2", "fakemail")],
    });

    // The exploding connector is reported as failed...
    const exploded = result.connectorResults.find((r) => r.connectorId === "exploder");
    expect(exploded?.ok).toBe(false);
    expect(exploded?.error).toContain("kaboom");

    // ...but the brief still generated from the healthy connector.
    expect(result.brief.sections[0].entries[0].headline).toBe(
      "Pay the overdue invoice",
    );
    expect(result.items).toHaveLength(1);
    expect(result.items[0].space).toBe("work"); // space stamped from connection
    expect(result.html).toContain("Pay the overdue invoice");
  });

  it("filters by space", async () => {
    const adapter = new StubModelAdapter(briefJson);
    const result = await runPipeline({
      ...base,
      adapter,
      connections: [conn("c2", "fakemail", "personal")],
      space: "work", // excludes the personal connection
    });
    expect(result.items).toHaveLength(0);
    // With no items, synthesize short-circuits to an empty brief (no model call).
    expect(adapter.calls).toHaveLength(0);
    expect(result.brief.sections).toEqual([]);
  });

  it("passes the assembled items to the model for synthesis", async () => {
    const adapter = new StubModelAdapter(briefJson);
    await runPipeline({
      ...base,
      adapter,
      connections: [conn("c2", "fakemail")],
    });
    expect(adapter.calls).toHaveLength(1);
    expect(adapter.calls[0].messages[0].content).toContain("Invoice overdue");
  });

  it("registry exposes the built-in gcal connector", () => {
    expect(getConnector("gcal")?.displayName).toBe("Google Calendar");
  });
});
