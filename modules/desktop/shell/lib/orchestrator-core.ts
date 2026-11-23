// The pure half of the bar's orchestrator cell: `▲ N · working/cap · orchestrator: <state> · held · <repos> paused`.
import type { Board } from "./board-core"
import type { Session } from "./sessions-core"

/** A line told to the orchestrator, from `at` (whole unix seconds, taken before babylon ran, as the records' are): `sent` until its turn on it starts, `on it` while it runs, `answered` after. */
export type Told = { at: number; phase: "sent" | "on it" | "answered" } | null

/** The turn that follows the tell starts (a working record from the tell's second on), then ends. A line babylon holds past a running turn waits for the next one. */
export function followTold(told: Told, session: Session | null): Told {
  if (!told || !session) return told
  if (told.phase === "sent" && session.state === "working" && session.since >= told.at) return { ...told, phase: "on it" }
  if (told.phase === "on it" && session.state !== "working") return { ...told, phase: "answered" }
  return told
}

export const CELL_WIDTH = 60

/** `held` and `paused` are their own pieces, each with its leading ` · `, so the bar can colour `held`; when the whole does not fit in `width` the paused part goes first, then the orchestrator's state, never the count. */
export type Cell = { text: string; held: string; paused: string; dim: boolean; attention: boolean }

export function cell(b: Board | null, session: Session | null, told: Told = null, width = CELL_WIDTH): Cell {
  const n = b?.needsYou.length ?? 0
  const o = b?.orchestrator
  const state = !o?.running ? (o?.on === false ? "off" : "restarting") : told ? (told.phase === "answered" ? "answered" : "on it") : session?.state === "working" ? "working" : session?.state === "waiting" ? "waits on you" : "idle"
  const lead = [`▲ ${n}`, ...(b ? [b.auto.on ? `${b.auto.working}/${b.auto.cap}` : "auto off"] : [])]
  const full = [...lead, `orchestrator: ${state}`].join(" · ")
  const held = b?.hold ? " · held" : ""
  const names = Object.entries(b?.auto.repo_caps ?? {}).filter(([, cap]) => cap === 0).map(([repo]) => repo).sort()
  const paused = names.length ? ` · ${names.join(", ")} paused` : ""
  const fits = (s: string) => s.length <= width
  const shown =
    fits(full + held + paused) ? { text: full, held, paused }
    : fits(full + held) ? { text: full, held, paused: "" }
    : { text: lead.join(" · "), held, paused: "" }
  return { ...shown, dim: n === 0, attention: state === "waits on you" }
}
