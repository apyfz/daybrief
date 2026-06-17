import { describe, it, expect } from "vitest";
import { parseStructuredBrief } from "./brief";

describe("parseStructuredBrief", () => {
  it("parses a clean structured brief", () => {
    const b = parseStructuredBrief(
      {
        date: "2026-06-17",
        summary: "Busy morning.",
        sections: [
          {
            kind: "priorities",
            title: "Priorities",
            entries: [{ headline: "Reply to Sarah", priority: 3 }],
          },
        ],
      },
      "2026-01-01",
    );
    expect(b.date).toBe("2026-06-17");
    expect(b.summary).toBe("Busy morning.");
    expect(b.sections).toHaveLength(1);
    expect(b.sections[0].entries[0].priority).toBe(3);
  });

  it("extracts JSON from a code-fenced string", () => {
    const raw = 'Here you go:\n```json\n{"date":"2026-06-17","sections":[]}\n```';
    const b = parseStructuredBrief(raw, "2026-01-01");
    expect(b.date).toBe("2026-06-17");
    expect(b.sections).toEqual([]);
  });

  it("orders known sections canonically", () => {
    const b = parseStructuredBrief(
      {
        date: "2026-06-17",
        sections: [
          { kind: "prep", entries: [{ headline: "x" }] },
          { kind: "priorities", entries: [{ headline: "y" }] },
          { kind: "schedule", entries: [{ headline: "z" }] },
        ],
      },
      "2026-01-01",
    );
    expect(b.sections.map((s) => s.kind)).toEqual([
      "priorities",
      "schedule",
      "prep",
    ]);
  });

  it("degrades malformed input to a valid empty brief", () => {
    const b = parseStructuredBrief("not json at all", "2026-01-01");
    expect(b.date).toBe("2026-01-01");
    expect(b.sections).toEqual([]);
  });

  it("drops entries without a headline", () => {
    const b = parseStructuredBrief(
      {
        date: "2026-06-17",
        sections: [
          { kind: "priorities", entries: [{ detail: "no headline" }, { headline: "ok" }] },
        ],
      },
      "2026-01-01",
    );
    expect(b.sections[0].entries).toHaveLength(1);
    expect(b.sections[0].entries[0].headline).toBe("ok");
  });
});
