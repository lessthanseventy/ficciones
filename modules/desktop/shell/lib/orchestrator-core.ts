// The pure half of the bar's orchestrator cell: `▲ N · orchestrator: <state>`.
import type { Board } from "./board-core"
import type { Session } from "./sessions-core"

export type Cell = { text: string; dim: boolean; attention: boolean }

/** A line told to the orchestrator, from `at` (whole unix seconds, taken before babylon ran, as the records' are): `sent` until its turn on it starts, `on it` while it runs, `answered` after. */
export type Told = { at: number; phase: "sent" | "on it" | "answered" } | null

/** The turn that follows the tell starts (a working record from the tell's second on), then ends. A line babylon holds past a running turn waits for the next one. */
export function followTold(told: Told, session: Session | null): Told {
  if (!told || !session) return told
  if (told.phase === "sent" && session.state === "working" && session.since >= told.at) return { ...told, phase: "on it" }
  if (told.phase === "on it" && session.state !== "working") return { ...told, phase: "answered" }
  return told
}

export function cell(b: Board | null, session: Session | null, told: Told = null): Cell {
  const n = b?.needsYou ?? 0
  const head = `▲ ${n} · orchestrator: `
  const o = b?.orchestrator
  const state = !o?.running ? (o?.on === false ? "off" : "restarting") : told ? (told.phase === "answered" ? "answered" : "on it") : session?.state === "working" ? "working" : session?.state === "waiting" ? "waits on you" : "idle"
  return { text: head + state, dim: n === 0, attention: state === "waits on you" }
}
