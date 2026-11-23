// The pure half of lib/sessions.ts: the records Claude Code's session hook keeps in
// $XDG_RUNTIME_DIR/sessions (arena's plugin), read for the deck.
import type { Sfx } from "./sfx-core"
import type { Card } from "./board-core"

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
  /** from the statusline's meter, `<id>.meter` beside the record */
  ctx?: number
  model?: string | null
}

const STATES: State[] = ["working", "done", "waiting"]
const ORDER: Record<State, number> = { waiting: 0, done: 1, working: 2 }
/** a turn this long that lands is worth a chime: you have likely looked away */
const LONG_TURN_S = 120

export function parse(text: string): Session | null {
  try {
    const r = JSON.parse(text)
    return typeof r?.id === "string" && STATES.includes(r.state) ? (r as Session) : null
  } catch { return null }
}

export function metered(s: Session, text: string | null): Session {
  try {
    const m = text ? JSON.parse(text) : null
    return typeof m?.ctx === "number" ? { ...s, ctx: m.ctx, model: m.model ?? null } : s
  } catch { return s }
}

/** a session outside tmux has no pane to ask after: one silent this long has likely crashed */
const SILENT_S = 24 * 3600

/** `live` holds "<socket> <pane>" for every pane the tmux servers have; a crash leaves a record behind */
export const alive = (s: Session, live: Set<string>, now: number) =>
  s.pane ? live.has(`${s.socket} ${s.pane}`) : now - s.at < SILENT_S

export const isCrew = (s: Session) => /\/tlon-workspace-[^/]*$/.test(s.socket)

export const mine = (all: Session[]) =>
  all.filter((s) => !isCrew(s)).sort((a, b) => ORDER[a.state] - ORDER[b.state] || a.repo.localeCompare(b.repo))

export const nextUp = (all: Session[]) => mine(all)[0] ?? null

/** what waits on you, in words: babylon's open asks (`asks`), then the sessions waiting on an answer */
export const waiting = (all: Session[], asks: Card[]): string[] => [
  ...asks.flatMap((t) => (t.ask ? [`#${t.id} asks: ${t.ask.question}`] : [])),
  ...mine(all).filter((s) => s.state === "waiting").map((s) => `${s.repo} waits${s.doing ? `: ${s.doing}` : ""}`),
]

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

/** the `-L` that reaches the session's tmux server */
export const arenaTarget = (s: { socket: string }) => ["-L", s.socket.split("/").pop() || "default"]

/** what `arena` takes to open its inbox (Your move); `socket` is the board's tmux server, null for the default one */
export const inboxArgs = (socket: string | null) => [...(socket ? arenaTarget({ socket }) : []), "inbox"]

/** arena's window in a client list: Ghostty joins a running instance and ignores `--class`, so the class is Ghostty's own or the one asked for, and the title `arena` (set by `--title`) tells it from other terminals */
export const findArena = <C extends { class: string; title: string }>(clients: C[]): C | undefined =>
  clients.find((c) => (c.class === "com.mitchellh.ghostty" || c.class === "com.ghostty.arena") && c.title === "arena")

/** what `arena` takes to open on a needs-you item: its ticket's card, or the inbox when it has no ticket */
export const itemArgs = (ticket: number | null, socket: string | null) =>
  ticket === null ? inboxArgs(socket) : [...(socket ? arenaTarget({ socket }) : []), "board", String(ticket)]
