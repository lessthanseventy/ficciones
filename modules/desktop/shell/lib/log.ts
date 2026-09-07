// The command log: what just happened, one line each, the way lazygit's log shows the git it
// ran. Sources colour the line (design: the bottom deck) — the shell's own actions, notices,
// agent events, Hyprland's events, journal warnings. Bounded; the deck's row shows the tail,
// its drawer the lot with source filters.
import { createState } from "ags"
import { hypr } from "./hypr"

export type Src = "shell" | "notice" | "agent" | "hypr" | "journal"
export type Level = "dim" | "normal" | "warn" | "crit"
export type Entry = { id: number; t: number; src: Src; text: string; level: Level }

const CAP = 400
let seq = 0
export const [log, setLog] = createState<Entry[]>([])

export function logEvent(src: Src, text: string, level: Level = "normal") {
  const e: Entry = { id: ++seq, t: Date.now(), src, text: text.replace(/\s+/g, " ").trim(), level }
  setLog((l) => (l.length >= CAP ? [...l.slice(l.length - CAP + 1), e] : [...l, e]))
}

export const hhmm = (t: number) => {
  const d = new Date(t)
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
}

// ── Hyprland: only what is rare and worth a line — monitors and config. Workspace switches
// and window open/close were tried and drowned the row (2026-09-07).
hypr.connect("event", (_, ev: string, args: string) => {
  switch (ev) {
    case "monitoradded": logEvent("hypr", `monitor ${args} plugged`); break
    case "monitorremoved": logEvent("hypr", `monitor ${args} gone`, "warn"); break
    case "configreloaded": logEvent("hypr", "config reloaded"); break
  }
})
