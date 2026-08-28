// manos — the claude-code adapter's auto-track hook (reshape slice B). Same shape as
// cc-heartbeat.ts: claude-machine has no persistent extension process, so a PostToolUse hook is a
// fresh bun process per tool call. When the tool call that just finished was a successful
// `git … commit`, this connection's thread promotes into the stage machine via `track_thread` —
// the ticket condenses out of the work. The server is idempotent, so firing on every commit is
// safe; no state file needed.
//
// Same failure discipline as the sibling hooks: funes down, no identity, an unparseable
// payload — all silent no-ops. A PostToolUse hook must never block or break a tool call.

import { env } from "node:process";
import { isCommitCommand } from "./activity.ts";
import { FunesClient } from "./mcp.ts";

const HOOK_TIMEOUT_MS = 10_000;

export interface PostToolUseInput {
  tool_name?: string;
  tool_input?: unknown;
  tool_response?: unknown;
}

// The pure gate: a Bash tool call whose command is a commit invocation and whose response does
// not read as a failure. Claude Code's Bash tool_response is `{stdout, stderr, interrupted, …}`
// with no single error flag, so failure is inferred: an interrupt, an explicit flag where one
// exists, or a stderr that names a git refusal. A wrong promote is NOT harmless (there is no
// demote verb — a thread where nothing landed would be staged "build" forever), so refusal
// shapes are checked first; only then does an unmarked response count as success.
const FAILURE_STDERR = /nothing to commit|fatal:|error:|rejected|hook failed|no changes added/i;

export function shouldTrack(input: PostToolUseInput): boolean {
  if (input.tool_name !== "Bash") return false;
  const cmd = (input.tool_input as Record<string, unknown> | null)?.["command"];
  if (typeof cmd !== "string" || !isCommitCommand(cmd)) return false;
  const response = input.tool_response as Record<string, unknown> | null;
  if (!response) return true;
  if (response["is_error"] === true || response["success"] === false) return false;
  if (response["interrupted"] === true) return false;
  // git writes "nothing to commit" to STDOUT and hook/ref refusals to STDERR — scan both.
  for (const key of ["stderr", "stdout"]) {
    const text = response[key];
    if (typeof text === "string" && FAILURE_STDERR.test(text)) return false;
  }
  return true;
}

async function track(): Promise<void> {
  const url = env.FUNES_MCP_URL;
  const threadEnv = env.FUNES_THREAD;
  const agent = env.FUNES_AUTHOR;
  if (!url || !threadEnv || !agent) return;
  const threadId = Number(threadEnv);
  if (!Number.isInteger(threadId)) return;

  let hookInput: PostToolUseInput;
  try {
    hookInput = JSON.parse(await Bun.stdin.text()) as PostToolUseInput;
  } catch {
    return;
  }
  if (!shouldTrack(hookInput)) return;

  const client = new FunesClient({ url, threadId, agent });
  await client.connect();
  await client.trackThread();
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main(): Promise<void> {
  try {
    await Promise.race([track(), delay(HOOK_TIMEOUT_MS)]);
  } catch {
    // silent no-op
  }
}

if (import.meta.main) {
  main().finally(() => process.exit(0));
}
