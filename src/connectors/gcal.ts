// Google Calendar connector (SPEC.md §8, M1). Clean path: Calendar API + OAuth.
// Pulls today + tomorrow's events. Also covers Notion Calendar, which is just a
// front-end over Google Calendar.
//
// Connectors fetch + normalize ONLY — no LLM, no render, no deliver.

import type {
  AuthorizedAccount,
  BriefItem,
  Connector,
  FetchOptions,
  OAuthConfig,
  RawItem,
  UrgencyHint,
} from "@/core/types";

const CALENDAR_API = "https://www.googleapis.com/calendar/v3";

/** Subset of the Google Calendar Event resource we consume. */
interface GCalEvent {
  id: string;
  status?: string; // "confirmed" | "tentative" | "cancelled"
  summary?: string;
  description?: string;
  htmlLink?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
  attendees?: { email?: string; displayName?: string; self?: boolean }[];
  organizer?: { email?: string; displayName?: string };
}

interface GCalListResponse {
  items?: GCalEvent[];
}

export const googleCalendarConnector: Connector = {
  id: "gcal",
  displayName: "Google Calendar",

  authenticate(): OAuthConfig {
    return {
      authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
      tokenUrl: "https://oauth2.googleapis.com/token",
      // Minimum scope: read-only events (SPEC.md §11).
      scopes: ["https://www.googleapis.com/auth/calendar.events.readonly"],
      redirect: { kind: "loopback" },
      // Calendar's readonly scope is NOT a Google "restricted" scope, so the
      // standard consent screen works. BYO-app still recommended for OSS trust,
      // but not strictly required like Gmail.
      bringYourOwnApp: false,
    };
  },

  async fetch(opts: FetchOptions): Promise<RawItem[]> {
    const results: RawItem[] = [];
    for (const acct of opts.accounts) {
      // One dead account must never kill the brief (SPEC.md §2). Isolate.
      try {
        const events = await fetchPrimaryCalendar(acct, opts);
        for (const ev of events) {
          results.push({ source: "gcal", account: acct.account.id, raw: ev });
        }
      } catch (err) {
        // Swallow per-account errors; the orchestrator records the failure.
        console.warn(`[gcal] fetch failed for ${acct.account.label}:`, err);
      }
    }
    return results;
  },

  normalize(raw: RawItem[]): BriefItem[] {
    const items: BriefItem[] = [];
    for (const r of raw) {
      if (r.source !== "gcal") continue;
      const ev = r.raw as GCalEvent;
      if (ev.status === "cancelled") continue;
      const start = eventStart(ev);
      if (!start) continue;

      items.push({
        source: "gcal",
        account: r.account,
        space: "", // filled in by the orchestrator from the Connection's space
        type: "event",
        title: ev.summary?.trim() || "(no title)",
        body: ev.description?.trim() || undefined,
        people: attendeeNames(ev),
        timestamp: start,
        url: ev.htmlLink,
        urgencyHints: urgencyHints(start),
      });
    }
    // Chronological within the day.
    items.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
    return items;
  },
};

async function fetchPrimaryCalendar(
  acct: AuthorizedAccount,
  opts: FetchOptions,
): Promise<GCalEvent[]> {
  const params = new URLSearchParams({
    timeMin: opts.since.toISOString(),
    timeMax: opts.until.toISOString(),
    singleEvents: "true", // expand recurring events into instances
    orderBy: "startTime",
    maxResults: "50",
  });
  const res = await opts.http.request({
    method: "GET",
    url: `${CALENDAR_API}/calendars/primary/events?${params.toString()}`,
    headers: { Authorization: `Bearer ${acct.credentials.accessToken}` },
  });
  if (!res.ok) {
    throw new Error(`gcal API ${res.status}: ${await res.text()}`);
  }
  const data = (await res.json()) as GCalListResponse;
  return data.items ?? [];
}

function eventStart(ev: GCalEvent): Date | undefined {
  const raw = ev.start?.dateTime ?? ev.start?.date;
  if (!raw) return undefined;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? undefined : d;
}

function attendeeNames(ev: GCalEvent): string[] | undefined {
  const names = (ev.attendees ?? [])
    .filter((a) => !a.self)
    .map((a) => a.displayName || a.email || "")
    .filter(Boolean);
  if (ev.organizer && !ev.organizer.email?.includes("calendar.google.com")) {
    const org = ev.organizer.displayName || ev.organizer.email;
    if (org && !names.includes(org)) names.unshift(org);
  }
  return names.length ? names : undefined;
}

function urgencyHints(start: Date): UrgencyHint[] | undefined {
  const hints: UrgencyHint[] = [];
  if (isSameLocalDay(start, new Date())) hints.push("scheduled-today");
  return hints.length ? hints : undefined;
}

function isSameLocalDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}
