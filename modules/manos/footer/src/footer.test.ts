import { describe, expect, test } from "bun:test";
import { contextBar, fmtCost, fmtTokens } from "./footer.ts";

describe("fmtTokens — human token counts", () => {
  test("0 / under 1k / k / M thresholds", () => {
    expect(fmtTokens(0)).toBe("0");
    expect(fmtTokens(512)).toBe("512");
    expect(fmtTokens(1_500)).toBe("1.5k");
    expect(fmtTokens(2_400_000)).toBe("2.4M");
  });
});

describe("fmtCost — money, or nothing when free", () => {
  test("0 is blank; sub-cent shows 4 places; else 2", () => {
    expect(fmtCost(0)).toBe("");
    expect(fmtCost(0.0004)).toBe("$0.0004");
    expect(fmtCost(0.42)).toBe("$0.42");
    expect(fmtCost(12.5)).toBe("$12.50");
  });
});

describe("contextBar — proportional fill, clamped", () => {
  test("fills proportionally to width", () => {
    expect(contextBar(0, 10)).toBe("░".repeat(10));
    expect(contextBar(50, 10)).toBe("▓".repeat(5) + "░".repeat(5));
    expect(contextBar(100, 10)).toBe("▓".repeat(10));
  });

  test("context overflow (pct > 100) clamps instead of crashing String.repeat with a negative", () => {
    // The bug this pins: an unclamped `width - filled` goes negative past 100% and throws.
    expect(() => contextBar(150, 10)).not.toThrow();
    expect(contextBar(150, 10)).toBe("▓".repeat(10));
    expect(contextBar(-20, 10)).toBe("░".repeat(10));
  });
});
