import { describe, expect, test } from "bun:test";
import { shouldTrack } from "./cc-track.ts";

describe("shouldTrack — the PostToolUse gate for auto-tracking (reshape slice B)", () => {
  test("a successful Bash git commit tracks", () => {
    expect(shouldTrack({ tool_name: "Bash", tool_input: { command: "git commit -m 'x'" } })).toBe(true);
    expect(
      shouldTrack({
        tool_name: "Bash",
        tool_input: { command: "git add -A && git commit -F msg" },
        tool_response: { stdout: "[main abc123] x" },
      }),
    ).toBe(true);
  });

  test("non-Bash tools and non-commit commands do not", () => {
    expect(shouldTrack({ tool_name: "Edit", tool_input: { command: "git commit" } })).toBe(false);
    expect(shouldTrack({ tool_name: "Bash", tool_input: { command: "git status" } })).toBe(false);
    expect(shouldTrack({ tool_name: "Bash" })).toBe(false);
    expect(shouldTrack({})).toBe(false);
  });

  test("a response that reads as failure does not track", () => {
    expect(
      shouldTrack({
        tool_name: "Bash",
        tool_input: { command: "git commit -m x" },
        tool_response: { is_error: true },
      }),
    ).toBe(false);
    expect(
      shouldTrack({
        tool_name: "Bash",
        tool_input: { command: "git commit -m x" },
        tool_response: { success: false },
      }),
    ).toBe(false);
  });
});
