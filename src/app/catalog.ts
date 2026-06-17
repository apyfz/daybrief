// UI-facing catalog of connectors: display metadata + auth guidance. The fetch/
// normalize logic lives in the connector itself (src/connectors); this is only
// what the Connections screen needs to render and guide setup.

export interface ConnectorCatalogEntry {
  id: string;
  name: string;
  icon: string; // emoji placeholder until real icons
  blurb: string;
  /** Implemented end-to-end today, vs. planned (greyed out in UI). */
  status: "available" | "planned";
  /** Bring-your-own OAuth app required (Gmail, Slack — SPEC.md §8). */
  bringYourOwnApp?: boolean;
  setupSteps?: string[];
}

export const CONNECTOR_CATALOG: ConnectorCatalogEntry[] = [
  {
    id: "gcal",
    name: "Google Calendar",
    icon: "📅",
    blurb: "Today + tomorrow's events. Also covers Notion Calendar.",
    status: "available",
    bringYourOwnApp: false,
  },
  {
    id: "gmail",
    name: "Gmail",
    icon: "✉️",
    blurb: "Unread / important mail in the last 24h. Multi-account.",
    status: "planned",
    bringYourOwnApp: true,
    setupSteps: [
      "Create a Google Cloud project and enable the Gmail API.",
      "Configure an OAuth consent screen (External, Testing is fine).",
      "Create an OAuth client ID of type 'Desktop app'.",
      "Paste the client ID + secret here. The gmail.readonly scope is a Google restricted scope, so your own client is the clean path.",
    ],
  },
  {
    id: "slack",
    name: "Slack",
    icon: "💬",
    blurb: "Mentions + DMs in the last 24h. One app per workspace.",
    status: "planned",
    bringYourOwnApp: true,
    setupSteps: [
      "Create a Slack app at api.slack.com/apps for your workspace.",
      "Add user-token scopes: channels:history, im:history, users:read.",
      "Install the app to your workspace (internal/custom app — no Marketplace rate limits).",
      "Paste the User OAuth token here.",
    ],
  },
];

export function catalogEntry(id: string): ConnectorCatalogEntry | undefined {
  return CONNECTOR_CATALOG.find((c) => c.id === id);
}
