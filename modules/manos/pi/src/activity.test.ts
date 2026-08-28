import { describe, expect, test } from "bun:test";
import {
  buildHeartbeatPrompt,
  fallbackLine,
  formatDuration,
  lastToolActivity,
  phraseHeartbeat,
  type Entry,
} from "./activity.ts";

const asstText = (text: string): Entry => ({ message: { role: "assistant", content: [{ type: "text", text }] } });
const toolUse = (name: string, input?: unknown): Entry => ({
  message: { role: "assistant", content: [{ type: "tool_use", name, input }] },
});

describe("lastToolActivity — the mechanical signal, no LLM involved", () => {
  test("no entries yet → undefined", () => {
    expect(lastToolActivity([])).toBeUndefined();
  });

  test("entries with no tool_use block → undefined", () => {
    expect(lastToolActivity([asstText("just thinking out loud")])).toBeUndefined();
  });

  test("finds the most recent tool_use, scanning from the end", () => {
    const entries = [toolUse("Read", { file_path: "/a.ex" }), toolUse("Bash", { command: "mix test" })];
    expect(lastToolActivity(entries)).toEqual({ name: "Bash", detail: "mix test" });
  });

  test("pulls the first recognized detail field (command over file_path)", () => {
    expect(lastToolActivity([toolUse("Bash", { command: "mix test", file_path: "/a.ex" })])).toEqual({
      name: "Bash",
      detail: "mix test",
    });
  });

  test("no recognized detail field → name only, no crash on odd input shapes", () => {
    expect(lastToolActivity([toolUse("Glob", { weird_key: 1 })])).toEqual({ name: "Glob", detail: undefined });
    expect(lastToolActivity([toolUse("NoInput")])).toEqual({ name: "NoInput", detail: undefined });
  });

  test("a long detail truncates rather than blowing up the message", () => {
    const long = "x".repeat(200);
    const got = lastToolActivity([toolUse("Bash", { command: long })]);
    expect(got?.detail?.length).toBeLessThan(90);
    expect(got?.detail?.endsWith("…")).toBe(true);
  });
});

describe("formatDuration — sub-minute-precise, mirrors the aleph-side Aleph.Text.duration/1", () => {
  test("under a minute is bare seconds", () => {
    expect(formatDuration(0)).toBe("0s");
    expect(formatDuration(45)).toBe("45s");
  });

  test("a minute or more is Mm Ss", () => {
    expect(formatDuration(60)).toBe("1m0s");
    expect(formatDuration(192)).toBe("3m12s");
  });

  test("an hour or more drops seconds", () => {
    expect(formatDuration(3_900)).toBe("1h5m");
  });

  test("negative clamps to 0s", () => {
    expect(formatDuration(-5)).toBe("0s");
  });
});

describe("fallbackLine — the never-silent mechanical line when the sidecar can't phrase one", () => {
  test("no activity yet", () => {
    expect(fallbackLine(undefined, 30)).toBe("still on it (30s)");
  });

  test("activity with a detail", () => {
    expect(fallbackLine({ name: "Bash", detail: "mix test" }, 192)).toBe("still on it (3m12s) — Bash: mix test");
  });

  test("activity with no detail", () => {
    expect(fallbackLine({ name: "Read" }, 5)).toBe("still on it (5s) — Read");
  });
});

describe("buildHeartbeatPrompt — pins the sidecar contract (short, plain, no questions)", () => {
  test("names the elapsed time and current activity, constrains the output shape", () => {
    const p = buildHeartbeatPrompt({ name: "Bash", detail: "mix test" }, 192);
    expect(p).toContain("3m12s");
    expect(p).toContain("Bash");
    expect(p).toContain("mix test");
    expect(p).toContain("ONE short");
    expect(p).toContain("no questions");
    expect(p).toContain("no markdown");
  });

  test("no activity yet reads as getting started, not a crash on undefined", () => {
    expect(buildHeartbeatPrompt(undefined, 5)).toContain("getting started");
  });
});

describe("phraseHeartbeat — the sidecar call, mechanical fallback on any hiccup", () => {
  test("uses the sidecar's phrasing, trimmed to its first line", async () => {
    const complete = async () => "  still chasing down that flaky test, hang tight  \nextra";
    const line = await phraseHeartbeat({ name: "Bash", detail: "mix test" }, 30, complete);
    expect(line).toBe("still chasing down that flaky test, hang tight");
  });

  test("an empty completion falls back to the mechanical line", async () => {
    const complete = async () => "   ";
    const line = await phraseHeartbeat({ name: "Bash", detail: "mix test" }, 30, complete);
    expect(line).toBe(fallbackLine({ name: "Bash", detail: "mix test" }, 30));
  });

  test("a throwing completion (sidecar unreachable) falls back — never silent", async () => {
    const complete = async () => {
      throw new Error("OLLAMA_API_KEY not set");
    };
    const line = await phraseHeartbeat(undefined, 5, complete);
    expect(line).toBe(fallbackLine(undefined, 5));
  });
});
