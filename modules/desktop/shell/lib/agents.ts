// The Tlön roster + thread counts for the AGENTS pane, via scripts/tlon-cli.sh shell-status
// (an rpc into the always-up server node). Polled; "channel down" when the server is not up.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { logEvent } from "./log"

/** `prompt`: its coworker is sitting on a dialog (Server.Attention) — the ask, answered from the thread */
export type Thread = { id: number; title: string; stage: string | null; awaiting: string | null; prompt?: { summary: string } | null }
export type Agents = {
  ok: boolean
  roster: { agent: string; thread_id: number; title: string; warm: boolean }[]
  /** every open thread, newest first — the pane's rows; a staffed one carries its roster entry */
  threads: Thread[]
  counts: Record<string, number>
  awaiting: number
  note?: string
}
/** a thread's brief, the scope get_dossier hands an agent (scripts/tlon-cli.sh shell-dossier) */
export type Dossier = {
  thread_id: number
  goal: string | null
  lead: string | null
  next: string | null
  recent: { at: string; author: string; body: string }[]
  blockers: { shown: { text?: string; title?: string }[]; more: number }
  todos?: { shown: { text?: string; title?: string }[]; more: number }
  done: { shown: unknown[]; more: number }
}
export async function dossier(id: number): Promise<Dossier | null> {
  try {
    const out = await execAsync([CLI, "shell-dossier", String(id)])
    return JSON.parse(out.trim().split("\n").pop() ?? "null")
  } catch { return null }
}

// Single-user machine, fixed checkout — the same assumption flake.nix makes.
const CLI = "/home/andrew/projects/tlon/scripts/tlon-cli.sh"

// the command log gets the changes, not the polls: who woke, who slept, who waits on you
let last: Agents | null = null
function diff(next: Agents) {
  if (last?.ok) {
    const warm = new Map(last.roster.map((r) => [r.agent, r.warm]))
    for (const r of next.roster) {
      const was = warm.get(r.agent)
      if (was === undefined) logEvent("agent", `${r.agent} joined · ${r.title}`)
      else if (was !== r.warm) logEvent("agent", `${r.agent} ${r.warm ? "woke" : "went cold"}`, r.warm ? "normal" : "dim")
    }
    for (const r of last.roster) if (!next.roster.some((x) => x.agent === r.agent)) logEvent("agent", `${r.agent} left`, "dim")
    if (next.awaiting !== last.awaiting) logEvent("agent", next.awaiting ? `${next.awaiting} awaiting you` : "nothing awaits you", next.awaiting ? "warn" : "dim")
    // the needs-you signal OUTSIDE any window (field baseline: every platform has one): a toast
    // through our own notifd when more threads wait on the operator than before
    if (next.awaiting > last.awaiting)
      execAsync(["notify-send", "-a", "tlön", "-u", "normal", "tlön needs you", `${next.awaiting} thread${next.awaiting === 1 ? "" : "s"} awaiting you`]).catch(() => void 0)
    // a coworker stuck on a permission dialog names what it is asking about, so the toast is the ask
    const asked = new Set(last.threads.filter((t) => t.prompt).map((t) => t.id))
    for (const t of next.threads)
      if (t.prompt && !asked.has(t.id))
        execAsync(["notify-send", "-a", "tlön", "-u", "normal", `#${t.id} ${t.title} is waiting on you`, t.prompt.summary]).catch(() => void 0)
  } else if (last && !last.ok) logEvent("agent", "channel up")
  last = next
}

export const agents = createPoll<Agents>(
  { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, note: "…" },
  30_000,
  async () => {
    try {
      const out = await execAsync([CLI, "shell-status"])
      const j = JSON.parse(out.trim().split("\n").pop() ?? "{}")
      const next: Agents = { ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0 }
      diff(next)
      return next
    } catch (e) {
      if (last?.ok) logEvent("agent", "channel down", "warn")
      last = { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, note: "channel down" }
      return last
    }
  },
)
