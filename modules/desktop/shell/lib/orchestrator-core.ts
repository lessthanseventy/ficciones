// The pure half of the bar's orchestrator cell: `▲ N · orchestrator: <state>`.
import type { Board } from "./board-core"
import type { Session } from "./sessions-core"

/** a line told to the orchestrator: `on it` until its turn lands, then `answered` until arena shows the column */
export type Told = { at: number; phase: "on it" | "answered" } | null

export type Cell = { text: string; dim: boolean; attention: boolean }

/** what arena's header counts: open asks, open proposals, and send-backs no Claude holds and nothing blocks */
export function yourMove(b: Board | null): number {
  if (!b) return 0
  const free = b.tickets.filter((t) => t.stage === "failed" && t.status === "doing" && !t.claimed_by && !t.blocked_by?.length)
  return b.tickets.filter((t) => t.ask).length + b.proposals + free.length
}

/** `on it` becomes `answered` when the orchestrator's session lands a turn that began after the line was told */
export function followTold(told: Told, session: Session | null): Told {
  if (told?.phase === "on it" && session?.state === "done" && session.since > told.at) return { ...told, phase: "answered" }
  return told
}

export function cell(b: Board | null, session: Session | null, told: Told): Cell {
  const n = yourMove(b)
  const head = `▲ ${n} · orchestrator: `
  const o = b?.orchestrator
  const state = !o?.running ? (o?.on === false ? "off" : "restarting") : told ? told.phase : session?.state === "working" ? "working" : session?.state === "waiting" ? "waits on you" : "idle"
  return { text: head + state, dim: n === 0, attention: state === "waits on you" }
}
