// Core domain types for Daybrief. These are the stable contracts that the
// orchestrator, connectors, normalizer, LLM adapter and renderer all share.
// See SPEC.md §6 (LLM adapter) and §7 (connector plugin contract).

// ---------------------------------------------------------------------------
// Spaces (SPEC.md §5)
// ---------------------------------------------------------------------------

/** A Space is just a tag on a Connection. Default Work / Personal; custom allowed. */
export type SpaceId = string; // "work" | "personal" | custom

export interface Space {
  id: SpaceId;
  label: string;
}

export const DEFAULT_SPACES: Space[] = [
  { id: "work", label: "Work" },
  { id: "personal", label: "Personal" },
];

// ---------------------------------------------------------------------------
// Connections & accounts (SPEC.md §3, §7)
// ---------------------------------------------------------------------------

/**
 * One authorization of a provider. Multi-account: each authorization is a
 * distinct Connection. A connection is tagged with exactly one Space.
 */
export interface Connection {
  id: string; // stable uuid
  connectorId: string; // which connector ("gcal", "gmail", "slack", ...)
  account: Account; // the connected account
  space: SpaceId;
  enabled: boolean;
  createdAt: string; // ISO timestamp
}

/** A single account belonging to a provider. One provider can have N accounts. */
export interface Account {
  id: string; // provider-local account id (email, workspace id, ...)
  label: string; // human label shown in UI (email address, workspace name)
}

// ---------------------------------------------------------------------------
// Connector contract (SPEC.md §7)
// ---------------------------------------------------------------------------

/** Minimal OAuth description a connector returns from authenticate(). */
export interface OAuthConfig {
  /** Authorization endpoint. */
  authUrl: string;
  /** Token exchange endpoint. */
  tokenUrl: string;
  /** Scopes requested — keep minimal and documented (SPEC.md §11). */
  scopes: string[];
  /**
   * Redirect handling. Desktop apps use a loopback redirect
   * (http://127.0.0.1:<port>/callback) or a custom scheme.
   */
  redirect: { kind: "loopback" } | { kind: "scheme"; scheme: string };
  /**
   * Some providers (Gmail, Slack) require a bring-your-own OAuth app:
   * the user supplies their own client id/secret (SPEC.md §8).
   */
  bringYourOwnApp?: boolean;
  /** Human guidance shown during the BYO-app setup flow. */
  setupSteps?: string[];
}

/** Opaque per-account credential bundle, resolved from the OS keychain. */
export interface AccountCredentials {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number; // epoch ms
  /** BYO-app client credentials, when the provider requires them. */
  clientId?: string;
  clientSecret?: string;
  /** Anything connector-specific (e.g. Slack team id). */
  extra?: Record<string, string>;
}

/** An account paired with its resolved credentials, handed to fetch(). */
export interface AuthorizedAccount {
  account: Account;
  space: SpaceId;
  credentials: AccountCredentials;
}

/** Raw, provider-shaped payload before normalization. */
export interface RawItem {
  source: string; // connector id
  account: string; // account id this came from
  raw: unknown; // provider payload, connector understands its own shape
}

export interface FetchOptions {
  accounts: AuthorizedAccount[];
  since: Date;
  until: Date;
  /** Allows a connector to make HTTP calls (Tauri http in app, fetch in tests). */
  http: HttpClient;
}

/**
 * Connectors fetch and normalize ONLY — never call the LLM, render or deliver
 * (SPEC.md §7). Keeping them dumb makes community PRs safe.
 */
export interface Connector {
  id: string;
  displayName: string;
  /** Scopes / redirect handling for first-time authorization. */
  authenticate(): OAuthConfig;
  /** Pull a window of raw items for the given authorized accounts. */
  fetch(opts: FetchOptions): Promise<RawItem[]>;
  /** Map provider payloads to the common BriefItem shape. */
  normalize(raw: RawItem[]): BriefItem[];
}

// ---------------------------------------------------------------------------
// Normalized item (SPEC.md §7)
// ---------------------------------------------------------------------------

export type UrgencyHint =
  | "unread"
  | "@mention"
  | "due-today"
  | "scheduled-today"
  | (string & {}); // open for connector-specific hints

export interface BriefItem {
  source: string; // connector id
  account: string; // which connected account
  space: SpaceId; // "work" | "personal" | custom
  type: string; // "email" | "message" | "event" | "comment" | "draft" ...
  title: string;
  body?: string;
  people?: string[];
  timestamp: Date;
  url?: string; // deep link to the original
  urgencyHints?: UrgencyHint[];
}

// ---------------------------------------------------------------------------
// HTTP client abstraction
// ---------------------------------------------------------------------------

/**
 * Tiny HTTP surface so connectors can run both inside Tauri (via the Tauri
 * http plugin, which avoids CORS) and inside unit tests (via injected fetch).
 */
export interface HttpClient {
  request(req: HttpRequest): Promise<HttpResponse>;
}

export interface HttpRequest {
  method: "GET" | "POST" | "PUT" | "DELETE" | "PATCH";
  url: string;
  headers?: Record<string, string>;
  body?: string;
}

export interface HttpResponse {
  status: number;
  ok: boolean;
  text(): Promise<string>;
  json(): Promise<unknown>;
}
