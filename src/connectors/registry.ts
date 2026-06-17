// Connector registry. Connectors register here; the orchestrator looks them up
// by id. Adding a connector = adding one entry (SPEC.md §7 extensibility).

import type { Connector } from "@/core/types";
import { googleCalendarConnector } from "./gcal";

const REGISTRY = new Map<string, Connector>();

export function registerConnector(connector: Connector): void {
  REGISTRY.set(connector.id, connector);
}

export function getConnector(id: string): Connector | undefined {
  return REGISTRY.get(id);
}

export function listConnectors(): Connector[] {
  return [...REGISTRY.values()];
}

// --- Built-in connectors -------------------------------------------------
// M1: Google Calendar. M2 adds Gmail + Slack (BYO app). M4 adds the rest.
registerConnector(googleCalendarConnector);
