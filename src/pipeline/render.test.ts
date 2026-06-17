import { describe, it, expect } from "vitest";
import { renderBriefDocument, renderBriefText } from "./render";
import type { StructuredBrief } from "@/core/brief";

const brief: StructuredBrief = {
  date: "2026-06-17",
  summary: "Two things need you.",
  sections: [
    {
      kind: "priorities",
      title: "Priorities",
      entries: [
        {
          headline: "Reply to <Sarah>",
          detail: "Re: contract",
          url: "https://mail/1",
          priority: 3,
        },
      ],
    },
    { kind: "slipped", title: "Empty", entries: [] },
  ],
};

describe("render", () => {
  it("produces a standalone HTML document", () => {
    const html = renderBriefDocument(brief);
    expect(html.startsWith("<!doctype html>")).toBe(true);
    expect(html).toContain("Two things need you.");
    expect(html).toContain('href="https://mail/1"');
  });

  it("escapes HTML in user content", () => {
    const html = renderBriefDocument(brief);
    expect(html).toContain("Reply to &lt;Sarah&gt;");
    expect(html).not.toContain("Reply to <Sarah>");
  });

  it("omits empty sections", () => {
    const html = renderBriefDocument(brief);
    expect(html).not.toContain(">Empty<");
  });

  it("renders a readable plain-text fallback", () => {
    const text = renderBriefText(brief);
    expect(text).toContain("Daybrief — 2026-06-17");
    expect(text).toContain("• Reply to <Sarah>");
  });
});
