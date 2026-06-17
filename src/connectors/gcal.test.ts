import { describe, it, expect } from "vitest";
import { googleCalendarConnector as gcal } from "./gcal";
import { StubHttpClient } from "@/core/testing";
import type { AuthorizedAccount, RawItem } from "@/core/types";

const account: AuthorizedAccount = {
  account: { id: "me@example.com", label: "me@example.com" },
  space: "work",
  credentials: { accessToken: "tok" },
};

describe("gcal connector", () => {
  it("requests a read-only calendar scope", () => {
    const cfg = gcal.authenticate();
    expect(cfg.scopes).toContain(
      "https://www.googleapis.com/auth/calendar.events.readonly",
    );
    expect(cfg.redirect).toEqual({ kind: "loopback" });
  });

  it("fetches events and tags them by account", async () => {
    const http = new StubHttpClient((req) =>
      req.url.includes("/calendars/primary/events")
        ? {
            json: {
              items: [
                {
                  id: "e1",
                  status: "confirmed",
                  summary: "Standup",
                  htmlLink: "https://cal/e1",
                  start: { dateTime: "2026-06-17T09:00:00Z" },
                  end: { dateTime: "2026-06-17T09:15:00Z" },
                  attendees: [
                    { email: "me@example.com", self: true },
                    { displayName: "Yasser" },
                  ],
                },
              ],
            },
          }
        : undefined,
    );
    const raw = await gcal.fetch({
      accounts: [account],
      since: new Date("2026-06-17T00:00:00Z"),
      until: new Date("2026-06-18T00:00:00Z"),
      http,
    });
    expect(raw).toHaveLength(1);
    expect(raw[0].account).toBe("me@example.com");
  });

  it("normalizes events, skips cancelled, and excludes self from people", () => {
    const raw: RawItem[] = [
      {
        source: "gcal",
        account: "me@example.com",
        raw: {
          id: "e1",
          status: "confirmed",
          summary: "Design review",
          start: { dateTime: "2026-06-17T15:00:00Z" },
          attendees: [
            { email: "me@example.com", self: true },
            { displayName: "Yasser" },
          ],
          htmlLink: "https://cal/e1",
        },
      },
      {
        source: "gcal",
        account: "me@example.com",
        raw: { id: "e2", status: "cancelled", summary: "Cancelled mtg" },
      },
    ];
    const items = gcal.normalize(raw);
    expect(items).toHaveLength(1);
    expect(items[0].type).toBe("event");
    expect(items[0].title).toBe("Design review");
    expect(items[0].people).toEqual(["Yasser"]);
    expect(items[0].url).toBe("https://cal/e1");
  });

  it("does not throw when a single account's fetch fails", async () => {
    const http = new StubHttpClient(() => ({ status: 500, text: "boom" }));
    const raw = await gcal.fetch({
      accounts: [account],
      since: new Date(),
      until: new Date(),
      http,
    });
    expect(raw).toEqual([]); // failure isolated, empty result
  });
});
