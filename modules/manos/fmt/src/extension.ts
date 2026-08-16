// manos/fmt — the agent's format-on-save. pi's `tool_result` middleware fires after every
// tool call; this extension watches `edit`/`write` and, when the touched file is an
// `.ex`/`.exs` inside a mix project, runs `mix format <file>` in that project's root so the
// file is always styler-compliant the instant the agent writes it. The `mix format
// --check-formatted` gate can then never fail for an agent-written file.
//
// Best-effort and invisible: a format failure never fails the edit (the tool_result is
// returned unchanged), and mix format is a no-op on already-compliant code. The one race:
// if mix format reformats a file the model just wrote, the model's NEXT edit's oldText (from
// its pre-format memory) can mismatch the formatted disk. The natural recovery is a re-read
// — and the model re-reads before editing files it didn't just write anyway. Net-positive:
// it eliminates the recurring format-check failure for the cost of a rare, self-recovering
// retry. See modules/manos/fmt/AGENTS.md.
//
// Only Elixir is formatted here — it's the only language in the stack whose gate runs a
// formatter (`mix format --check-formatted` in funes:check / aleph:check). TypeScript has no
// formatter in its gate (manos:consult:check is typecheck + tests), so there's nothing to
// auto-format for .ts. Diagnostics/typecheck for .ts is the LSP stack's job, not this one.

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI, ToolResultEvent, ToolResultPatch } from "./pi.ts";

export default function fmt(pi: ExtensionAPI): void {
  pi.on("tool_result", (event) => mixFormatTouched(event));
}

// The pure decision — which files to format and where — extracted so it's testable without
// spawning mix. Returns the {root, rel} to format, or null when the tool isn't edit/write,
// the path isn't .ex/.exs, or no mix.exs is found above the file.
export function formatTarget(event: ToolResultEvent): { root: string; rel: string } | null {
  if (event.toolName !== "edit" && event.toolName !== "write") return null;
  const file = (event.input as { path?: string } | null | undefined)?.path;
  if (!file || !/\.(ex|exs)$/i.test(file)) return null;
  const root = findMixRoot(file);
  if (!root) return null;
  return { root, rel: path.relative(root, file) };
}

async function mixFormatTouched(event: ToolResultEvent): Promise<ToolResultPatch | undefined> {
  const target = formatTarget(event);
  if (!target) return;
  await runQuiet("mix", ["format", target.rel], target.root);
  // Never modify the result — the edit stands; formatting is a silent side-effect.
  return undefined;
}

// Walk up from the file to the nearest mix.exs (capped — a project root is never deep).
export function findMixRoot(file: string): string | null {
  let dir = path.dirname(file);
  for (let i = 0; i < 12; i++) {
    if (fs.existsSync(path.join(dir, "mix.exs"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

// Fire-and-forget shell — resolve on close/error so the hook never hangs. stdio ignored:
// mix format is quiet on success and its output would be noise in the agent's view.
function runQuiet(cmd: string, args: string[], cwd: string): Promise<void> {
  return new Promise((resolve) => {
    const proc = spawn(cmd, args, { cwd, stdio: "ignore" });
    proc.on("close", () => resolve());
    proc.on("error", () => resolve());
  });
}