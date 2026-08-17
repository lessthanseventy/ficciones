// manos — the pi adapter (pi doc §2b). Three lifecycle hooks make a pi session a citizen
// of its funes thread: session_start registers (claims the pane, supersedes any zombie
// predecessor); before_agent_start injects the rendered dossier as the honest brief
// (aleph §3b: briefed from funes state, never a raw replay); turn_end refreshes the footer.
//
// Holds no state, touches no SQLite — calls funes through its own MCP client (mcp.ts).
// When funes is unreachable it surfaces the failure and does nothing else: no retry queue,
// no spill file (AGENTS.md, pi doc §2a).

import { env } from "node:process";
import { renderBrief, type Dossier } from "./brief.ts";
import { FunesClient, FunesUnreachable, type FunesConfig } from "./mcp.ts";
import type { ExtensionAPI, ExtensionContext } from "./pi.ts";

const STATUS_KEY = "funes";
const WIDGET_KEY = "funes";

// Identity travels in the spawn (pi doc §2d): FUNES_MCP_URL/THREAD/AUTHOR. No FUNES_TOKEN
// — the client mints a fresh token per connect against the URL's origin, so a pane survives
// a token-model change or secret regeneration. Missing any of the three means this pane
// wasn't spawned as a funes citizen; the adapter stays quiet rather than guessing.
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

  // One client for this pane's lifetime — connect() is guarded so only the first hook does
  // the handshake. register binds the session to the TOKEN, so the model's own tool calls
  // (a separate connection, same token) resolve this same session.
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
      return { message: { customType: "funes-brief", content: renderBrief(dossier, new Date(), env.PI_MODEL), display: true } };
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
