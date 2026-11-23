// The pure half of the bar's orchestrator cell: `▲ N · orchestrator: <state>`.
import type { Board } from "./board-core"
import type { Session } from "./sessions-core"

export type Cell = { text: string; dim: boolean; attention: boolean }

/** what arena's header counts: open asks, open proposals, and send-backs no Claude holds and nothing blocks */
export function yourMove(b: Board | null): number {
  if (!b) return 0
  const free = b.tickets.filter((t) => t.stage === "failed" && t.status === "doing" && !t.claimed_by && !t.blocked_by?.length)
  return b.tickets.filter((t) => t.ask).length + b.proposals + free.length
}

export function cell(b: Board | null, session: Session | null): Cell {
  const n = yourMove(b)
  const head = `▲ ${n} · orchestrator: `
  const o = b?.orchestrator
  const state = !o?.running ? (o?.on === false ? "off" : "restarting") : session?.state === "working" ? "working" : session?.state === "waiting" ? "waits on you" : "idle"
  return { text: head + state, dim: n === 0, attention: state === "waits on you" }
}
