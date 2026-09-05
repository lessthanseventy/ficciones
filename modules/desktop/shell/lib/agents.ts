// The Tlön roster + thread counts for the AGENTS pane, via scripts/tlon-cli.sh shell-status
// (an rpc into the always-up server node). Polled; "channel down" when the server is not up.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export type Agents = {
  ok: boolean
  roster: { agent: string; thread_id: number; title: string; warm: boolean }[]
  counts: Record<string, number>
  awaiting: number
  note?: string
}

// Single-user machine, fixed checkout — the same assumption flake.nix makes.
const CLI = "/home/andrew/projects/ficciones/scripts/tlon-cli.sh"

export const agents = createPoll<Agents>(
  { ok: false, roster: [], counts: {}, awaiting: 0, note: "…" },
  30_000,
  async () => {
    try {
      const out = await execAsync([CLI, "shell-status"])
      const j = JSON.parse(out.trim().split("\n").pop() ?? "{}")
      return { ok: true, roster: j.roster ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0 }
    } catch (e) {
      return { ok: false, roster: [], counts: {}, awaiting: 0, note: "channel down" }
    }
  },
)
