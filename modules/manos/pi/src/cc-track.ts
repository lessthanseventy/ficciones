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
// not read as a failure. Claude Code's Bash tool_response has no single error flag across
// versions, so this checks the shapes that exist (`is_error`, `success: false`) and otherwise
// assumes success — a false promote is idempotent and cheap; a missed one costs the workflow.
export function shouldTrack(input: PostToolUseInput): boolean {
  if (input.tool_name !== "Bash") return false;
  const cmd = (input.tool_input as Record<string, unknown> | null)?.["command"];
  if (typeof cmd !== "string" || !isCommitCommand(cmd)) return false;
  const response = input.tool_response as Record<string, unknown> | null;
  if (response && (response["is_error"] === true || response["success"] === false)) return false;
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
