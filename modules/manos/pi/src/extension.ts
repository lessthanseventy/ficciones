// manos — the pi adapter (pi doc §2b). The three lifecycle seams that make a pi session
// a citizen of its funes thread:
//
//   session_start      → register (claim the pane, supersede any zombie predecessor)
//   before_agent_start → get_dossier → render the honest brief → inject it, so the
//                        agent wakes already knowing its goal, learnings and blockers
//                        (aleph §3b's thesis: briefed from funes state, never a raw replay)
//   turn_end           → refresh the footer widget with live funes state
//
// The extension holds NO state and touches NO SQLite. It calls funes' channel through
// its own MCP client (mcp.ts); when funes is unreachable it surfaces the failure and
// does nothing else — no retry queue, no spill file (AGENTS.md, pi doc §2a).

import { env } from "node:process";
import { renderBrief, type Dossier } from "./brief.ts";
import { FunesClient, FunesUnreachable, type FunesConfig } from "./mcp.ts";
import type { ExtensionAPI, ExtensionContext } from "./pi.ts";

const STATUS_KEY = "funes";
const WIDGET_KEY = "funes";

// Identity travels in the spawn (pi doc §2d): the arbiter — the human, for these slices —
// exports FUNES_MCP_URL (the endpoint), FUNES_THREAD and FUNES_AUTHOR (the binding). No
// FUNES_TOKEN — the client mints a fresh token per connect against the URL's origin
// (POST /mint), so a pane survives a token-model change or a secret regeneration (the
// literal-tmux stale-401 fix). Missing any of the three means this pane was not spawned
// as a funes citizen; the adapter stays quiet rather than guessing.
function readConfig(): FunesConfig | null {
  const url = env.FUNES_MCP_URL;
  const thread = env.FUNES_THREAD;
  const author = env.FUNES_AUTHOR;
  if (!url || !thread || !author) return null;
  const threadId = Number(thread);
  if (!Number.isInteger(threadId)) return null;
  return { url, threadId, agent: author };
}

function identityLabel(): string {
  return `${env.FUNES_AUTHOR ?? "?"} on ${env.FUNES_THREAD ?? "?"}`;
}

export default function manos(pi: ExtensionAPI): void {
  const config = readConfig();

  // One client for this pane's lifetime — connect() is guarded, so every hook can await
  // it and only the first does the handshake. register binds the session to the TOKEN, so
  // the model's own tool calls (through pi-mcp-adapter, a separate connection, same token)
  // resolve this same session and keep it warm.
  const client = config ? new FunesClient(config) : null;

  pi.on("session_start", async (_event, ctx) => {
    if (!client) {
      ctx.ui.setStatus(STATUS_KEY, "funes: not wired (need FUNES_MCP_URL / FUNES_THREAD / FUNES_AUTHOR)");
      return;
    }
    try {
      await client.connect();
      await client.register(env.TMUX_PANE);
      ctx.ui.setStatus(STATUS_KEY, `funes: registered — ${identityLabel()}`);
    } catch (err) {
      surface(ctx, err);
    }
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    if (!client) return;
    try {
      await client.connect();
      const dossier = (await client.getDossier()) as Dossier;
      updateWidget(ctx, dossier);
      return { message: { customType: "funes-brief", content: renderBrief(dossier, new Date()), display: true } };
    } catch (err) {
      surface(ctx, err);
      return;
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (!client) return;
    try {
      await client.connect();
      updateWidget(ctx, (await client.getDossier()) as Dossier);
    } catch {
      // The footer is a nicety; a failed refresh must never interrupt or fail a turn.
    }
  });
}

// The footer: the live at-a-glance the human driving pi directly sees — the same dossier
// the cockpit shows (pi doc §2b). For slice 2 that is the goal and the open blockers; the
// TODOS line joins when slice 3 lands.
function updateWidget(ctx: ExtensionContext, d: Dossier): void {
  const lines = [`funes · ${d.north_star ?? "(untitled)"} — ${d.lead ?? "unstaffed"}`];
  const blockers = d.blockers.shown.length + d.blockers.more;
  if (blockers > 0) {
    lines.push(`blockers (${blockers}):`);
    for (const b of d.blockers.shown) lines.push(`  • ${b.summary}`);
    if (d.blockers.more > 0) lines.push(`  • … +${d.blockers.more} more`);
  } else {
    lines.push("no open blockers");
  }
  ctx.ui.setWidget(WIDGET_KEY, lines);
}

// Surface and stop (pi doc §2a): distinguish "funes is down" from "funes said no", show
// both, and do nothing else — no queue, no spill, no silent swallow.
function surface(ctx: ExtensionContext, err: unknown): void {
  const message = err instanceof Error ? err.message : String(err);
  const label = err instanceof FunesUnreachable ? "funes unreachable" : "funes error";
  ctx.ui.setStatus(STATUS_KEY, `${label}: ${message}`);
  ctx.ui.notify(`${label}: ${message}`, "error");
}
