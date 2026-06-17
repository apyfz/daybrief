import { describe, it, expect } from "vitest";
import { shouldCatchUp } from "./bootstrap";
import type { AppSettings, StoredBrief } from "./bridge";

const settings: AppSettings = {
  model: { kind: "openrouter", model: "m" },
  briefTime: "07:00",
  onboarded: true,
};

function briefOn(date: string): StoredBrief {
  return { date, generatedAt: `${date}T07:00:00Z`, html: "", json: "{}" };
}

describe("shouldCatchUp (generate-on-wake)", () => {
  it("catches up when scheduled time passed and no brief today", () => {
    const now = new Date("2026-06-17T09:00:00");
    expect(shouldCatchUp(settings, briefOn("2026-06-16"), now)).toBe(true);
  });

  it("does not catch up before the scheduled time", () => {
    const now = new Date("2026-06-17T06:30:00");
    expect(shouldCatchUp(settings, null, now)).toBe(false);
  });

  it("does not catch up when today's brief already exists", () => {
    const now = new Date("2026-06-17T09:00:00");
    expect(shouldCatchUp(settings, briefOn("2026-06-17"), now)).toBe(false);
  });

  it("does nothing until onboarded", () => {
    const now = new Date("2026-06-17T09:00:00");
    expect(shouldCatchUp({ ...settings, onboarded: false }, null, now)).toBe(
      false,
    );
  });
});
