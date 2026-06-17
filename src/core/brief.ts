// The structured brief: output of synthesis (SPEC.md §3 step 5), input to the
// renderer (step 6). The LLM is asked to return JSON matching `StructuredBrief`;
// `parseStructuredBrief` validates and repairs it defensively.

import type { SpaceId } from "./types";

/** A single actionable line in the brief, linked back to its source item. */
export interface BriefEntry {
  /** One-line editorial summary. */
  headline: string;
  /** Optional supporting detail. */
  detail?: string;
  /** Deep link to the original (carried through from the BriefItem). */
  url?: string;
  /** People involved, for clustering by person. */
  people?: string[];
  /** Where it came from, e.g. "gmail", "slack". */
  source?: string;
  /** Importance 1 (low) .. 3 (high), used for ordering within a section. */
  priority?: 1 | 2 | 3;
}

/** The canonical editorial sections (SPEC.md §1, §13). */
export type SectionKind =
  | "priorities" // what matters most today
  | "slipped" // what slipped overnight
  | "schedule" // today's schedule
  | "prep" // what to prep for
  | (string & {});

export interface BriefSection {
  kind: SectionKind;
  title: string;
  entries: BriefEntry[];
}

export interface StructuredBrief {
  /** ISO date this brief is for. */
  date: string;
  /** Optional one-paragraph editorial lede. */
  summary?: string;
  /** Which Space this brief covers (briefs can be split by Space — §5). */
  space?: SpaceId;
  sections: BriefSection[];
}

const KNOWN_SECTION_ORDER: SectionKind[] = [
  "priorities",
  "slipped",
  "schedule",
  "prep",
];

const SECTION_TITLES: Record<string, string> = {
  priorities: "Today's priorities",
  slipped: "What slipped overnight",
  schedule: "Today's schedule",
  prep: "What to prep for",
};

function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

function asString(v: unknown): string | undefined {
  return typeof v === "string" && v.trim().length > 0 ? v : undefined;
}

function asStringArray(v: unknown): string[] | undefined {
  if (!Array.isArray(v)) return undefined;
  const out = v.filter((x): x is string => typeof x === "string");
  return out.length ? out : undefined;
}

function asPriority(v: unknown): 1 | 2 | 3 | undefined {
  return v === 1 || v === 2 || v === 3 ? v : undefined;
}

function parseEntry(v: unknown): BriefEntry | null {
  if (typeof v !== "object" || v === null) return null;
  const o = v as Record<string, unknown>;
  const headline = asString(o.headline) ?? asString(o.title);
  if (!headline) return null;
  return {
    headline,
    detail: asString(o.detail) ?? asString(o.body),
    url: asString(o.url),
    people: asStringArray(o.people),
    source: asString(o.source),
    priority: asPriority(o.priority),
  };
}

function parseSection(v: unknown): BriefSection | null {
  if (typeof v !== "object" || v === null) return null;
  const o = v as Record<string, unknown>;
  const kind = asString(o.kind) ?? "priorities";
  const entries = asArray(o.entries)
    .map(parseEntry)
    .filter((e): e is BriefEntry => e !== null);
  const title = asString(o.title) ?? SECTION_TITLES[kind] ?? kind;
  return { kind, title, entries };
}

/**
 * Defensively parse model output into a StructuredBrief. Accepts a parsed
 * object or a raw JSON string (optionally wrapped in a ```json fence). Never
 * throws — a malformed brief degrades to an empty-but-valid structure so one
 * bad model response can't crash the pipeline (SPEC.md §2: resilience).
 */
export function parseStructuredBrief(
  input: unknown,
  fallbackDate: string,
): StructuredBrief {
  let value = input;
  if (typeof value === "string") {
    value = extractJson(value);
  }
  if (typeof value !== "object" || value === null) {
    return { date: fallbackDate, sections: [] };
  }
  const o = value as Record<string, unknown>;
  const sections = asArray(o.sections)
    .map(parseSection)
    .filter((s): s is BriefSection => s !== null);

  // Stable ordering: known editorial sections first, in canonical order.
  sections.sort((a, b) => {
    const ai = KNOWN_SECTION_ORDER.indexOf(a.kind);
    const bi = KNOWN_SECTION_ORDER.indexOf(b.kind);
    return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
  });

  return {
    date: asString(o.date) ?? fallbackDate,
    summary: asString(o.summary),
    space: asString(o.space),
    sections,
  };
}

/** Pull a JSON object out of a string that may contain prose or a code fence. */
function extractJson(s: string): unknown {
  const fence = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fence ? fence[1] : s;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) return null;
  try {
    return JSON.parse(candidate.slice(start, end + 1));
  } catch {
    return null;
  }
}
