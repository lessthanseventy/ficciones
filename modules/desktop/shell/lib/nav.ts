// The drawer's lazygit state: which pane has focus, and a cursor inside each pane. Tab cycles
// the focus — the log's filter chips, the log, the agents — j/k (or h/l along the chips) move
// the cursor in it, Enter acts (Deck.tsx wires the keys; Andrew, 2026-09-07).
import { createState } from "ags"

export const PANES = ["FILTERS", "LOG", "AGENTS"] as const
export type Pane = (typeof PANES)[number]

export const [focus, setFocus] = createState<Pane>("LOG")
export const [cursor, setCursor] = createState<Record<Pane, number>>({ FILTERS: 0, LOG: 0, AGENTS: 0 })

export const cursorOf = (p: Pane) => cursor((c) => c[p])
export const focused = (p: Pane) => focus((f) => f === p)
export function cycleFocus(dir: 1 | -1 = 1) {
  const i = PANES.indexOf(focus.get())
  setFocus(PANES[(i + dir + PANES.length) % PANES.length])
}
/** move the focused pane's cursor by delta, wrapping over `count` rows */
export function move(delta: number, count: number) {
  const p = focus.get()
  if (count <= 0) return
  setCursor((c) => ({ ...c, [p]: (((c[p] + delta) % count) + count) % count }))
}
export function jump(i: number, count: number) {
  const p = focus.get()
  if (count <= 0) return
  setCursor((c) => ({ ...c, [p]: Math.max(0, Math.min(count - 1, i)) }))
}
export function select(p: Pane, i: number) {
  setFocus(p)
  setCursor((c) => ({ ...c, [p]: i }))
}
