// The pure half of lib/alerts.ts — no gi imports, so node can test it (lib/alerts-core.test.mjs).
import type { Sfx } from "./sfx-core"

export type Action = { label: string; method?: string; path?: string; body?: Record<string, unknown> | null; input?: string; open?: string; read?: string }
export type Alert = {
  key: string; level: "alarm" | "decision" | "sticky" | "info"; kind: string; title: string; body: string | null
  at: string; thread_id: number | null; link: string | null; actions: Action[]
}
/** keys dismissed for good, and keys snoozed until a unix time */
export type Kept = { dismissed: string[]; snoozed: Record<string, number> }

/** The alerts still up at unix time `t`: neither dismissed nor snoozed past it. */
export const showing = (as: Alert[], k: Kept, t: number) =>
  as.filter((a) => !k.dismissed.includes(a.key) && !((k.snoozed[a.key] ?? 0) > t))

/** Whether the server can put `a` away itself — then that, not the desktop's own Dismiss, clears it,
 * so the desktop and the office inbox never disagree. */
export const putsAway = (a: Alert) => a.actions.some((x) => x.path === "/api/office/needs/dismiss")

/** The alerts in `fresh` this shell has not heard before and has not dismissed: what earns a sound,
 * once per key (`heard` is every key seen so far, the first poll's included, so a restart is quiet). */
export const arrived = (fresh: Alert[], heard: Set<string>, k: Kept) =>
  fresh.filter((a) => !heard.has(a.key) && !k.dismissed.includes(a.key))

/** the sound an arriving alert earns: a decision, or a landing (an info row of kind `landed`) */
export const soundFor = (a: Alert): Sfx | null => (a.level === "decision" ? "decision" : a.kind === "landed" ? "landing" : null)

export const ofLevel = (as: Alert[], level: Alert["level"]) => as.filter((a) => a.level === level)

/** The operator-API call an action makes, `text` filling its `input` field; null when it makes none. */
export function request(x: Action, text?: string): { method: string; path: string; body: Record<string, unknown> } | null {
  if (!x.path) return null
  const body = x.input ? { ...(x.body ?? {}), [x.input]: text ?? "" } : x.body ?? {}
  return { method: x.method ?? "POST", path: x.path, body }
}
