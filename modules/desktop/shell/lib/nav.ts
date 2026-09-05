// The drawer's lazygit state: which pane has focus, and a cursor inside each pane.
import { createState } from "ags"

export const PANES = ["AGENTS", "MEDIA", "WEATHER", "CALENDAR"] as const
export type Pane = (typeof PANES)[number]

export const [focus, setFocus] = createState<Pane>("AGENTS")
export const [cursor, setCursor] = createState<Record<Pane, number>>({ CALENDAR: 0, MEDIA: 0, WEATHER: 0, AGENTS: 0 })

export const cursorOf = (p: Pane) => cursor((c) => c[p])
export function move(delta: number, count: number) {
  const p = focus.get()
  if (count <= 0) return
  setCursor((c) => ({ ...c, [p]: ((c[p] + delta) % count + count) % count }))
}
export function select(p: Pane, i: number) {
  setFocus(p)
  setCursor((c) => ({ ...c, [p]: i }))
}
