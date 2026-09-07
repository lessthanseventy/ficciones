// The Tlön roster + thread counts for the AGENTS pane, via scripts/tlon-cli.sh shell-status
// (an rpc into the always-up server node). Polled; "channel down" when the server is not up.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { logEvent } from "./log"

export type Agents = {
  ok: boolean
  roster: { agent: string; thread_id: number; title: string; warm: boolean }[]
  counts: Record<string, number>
  awaiting: number
  note?: string
}

// Single-user machine, fixed checkout — the same assumption flake.nix makes.
const CLI = "/home/andrew/projects/ficciones/scripts/tlon-cli.sh"

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
  } else if (last && !last.ok) logEvent("agent", "channel up")
  last = next
}

export const agents = createPoll<Agents>(
  { ok: false, roster: [], counts: {}, awaiting: 0, note: "…" },
  30_000,
  async () => {
    try {
      const out = await execAsync([CLI, "shell-status"])
      const j = JSON.parse(out.trim().split("\n").pop() ?? "{}")
      const next: Agents = { ok: true, roster: j.roster ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0 }
      diff(next)
      return next
    } catch (e) {
      if (last?.ok) logEvent("agent", "channel down", "warn")
      last = { ok: false, roster: [], counts: {}, awaiting: 0, note: "channel down" }
      return last
    }
  },
)
