// The pure half of lib/sessions.ts: the records Claude Code's session hook keeps in
// $XDG_RUNTIME_DIR/sessions (modules/agents/session-state.sh), read for the bar.
import type { Sfx } from "./sfx-core"

export type State = "working" | "done" | "waiting"
export type Session = {
  id: string
  state: State
  since: number
  at: number
  cwd: string
  repo: string
  socket: string
  pane: string
  said: string | null
  doing: string | null
}
export type Tally = Record<State, number>

const STATES: State[] = ["working", "done", "waiting"]
const MARK: Record<State, string> = { working: "◌", done: "◉", waiting: "▲" }
const ORDER: Record<State, number> = { waiting: 0, done: 1, working: 2 }
/** a turn this long that lands is worth a chime: you have likely looked away */
const LONG_TURN_S = 120

export function parse(text: string): Session | null {
  try {
    const r = JSON.parse(text)
    return typeof r?.id === "string" && STATES.includes(r.state) ? (r as Session) : null
  } catch { return null }
}

/** `live` holds "<socket> <pane>" for every pane the tmux servers have; a crash leaves a record behind */
export const alive = (s: Session, live: Set<string>) => !s.pane || live.has(`${s.socket} ${s.pane}`)

export const isCrew = (s: Session) => /\/tlon-workspace-[^/]*$/.test(s.socket)

export const mine = (all: Session[]) =>
  all.filter((s) => !isCrew(s)).sort((a, b) => ORDER[a.state] - ORDER[b.state] || a.repo.localeCompare(b.repo))

export const nextUp = (all: Session[]) => mine(all)[0] ?? null

export function tally(list: Session[]): Tally {
  const t: Tally = { working: 0, done: 0, waiting: 0 }
  for (const s of list) t[s.state]++
  return t
}

export function mark(t: Tally) {
  const parts = (["waiting", "done", "working"] as State[]).filter((k) => t[k] > 0).map((k) => `${MARK[k]}${t[k]}`)
  return parts.length ? parts.join(" ") : "no sessions"
}

/** the sounds a change from `before` to `after` earns */
export function chimes(before: Map<string, Session>, after: Session[], now: number): Sfx[] {
  const out: Sfx[] = []
  for (const s of after) {
    const was = before.get(s.id)
    if (!was || was.state === s.state) continue
    if (s.state === "waiting") out.push("decision")
    else if (s.state === "done" && was.state === "working" && now - was.since >= LONG_TURN_S) out.push("landing")
  }
  return out
}

function ago(s: number) {
  if (s < 60) return `${Math.max(0, Math.round(s))}s`
  if (s < 3600) return `${Math.floor(s / 60)}m`
  return `${Math.floor(s / 3600)}h`
}

export const line = (s: Session, now: number) =>
  [`${MARK[s.state]} ${s.repo}`, s.doing ?? s.said, ago(now - s.since)].filter(Boolean).join("  ")

/** the `-L` that reaches the session's tmux server */
export const arenaTarget = (s: Session) => ["-L", s.socket.split("/").pop() || "default"]
