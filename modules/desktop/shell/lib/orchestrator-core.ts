// The pure half of the bar's orchestrator cell: `▲ N · orchestrator: <state>`.
import type { Board } from "./board-core"
import type { Session } from "./sessions-core"

export type Cell = { text: string; dim: boolean; attention: boolean }

/** A line told to the orchestrator, from `at` (unix seconds): `sent` until its turn on it starts, `on it` while it runs, `answered` after. */
export type Told = { at: number; phase: "sent" | "on it" | "answered" } | null

/** The turn that follows the tell starts (a working record newer than the tell), then ends. A line babylon holds past a running turn waits for the next one. */
export function followTold(told: Told, session: Session | null): Told {
  if (!told || !session) return told
  if (told.phase === "sent" && session.state === "working" && session.since > told.at) return { ...told, phase: "on it" }
  if (told.phase === "on it" && session.state !== "working") return { ...told, phase: "answered" }
  return told
}

/** what arena's header counts: open asks, open proposals, and send-backs no Claude holds and nothing blocks */
export function yourMove(b: Board | null): number {
  if (!b) return 0
  const free = b.tickets.filter((t) => t.stage === "failed" && t.status === "doing" && !t.claimed_by && !t.blocked_by?.length)
  return b.tickets.filter((t) => t.ask).length + b.proposals + free.length
}

export function cell(b: Board | null, session: Session | null, told: Told = null): Cell {
  const n = yourMove(b)
  const head = `▲ ${n} · orchestrator: `
  const o = b?.orchestrator
  const state = !o?.running ? (o?.on === false ? "off" : "restarting") : told ? (told.phase === "answered" ? "answered" : "on it") : session?.state === "working" ? "working" : session?.state === "waiting" ? "waits on you" : "idle"
  return { text: head + state, dim: n === 0, attention: state === "waits on you" }
}
