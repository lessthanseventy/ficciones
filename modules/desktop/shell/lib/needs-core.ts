// The pure half of the desktop's needs-you notices: one notice per item id in board.json's needs_you.
import type { Item } from "./board-core"

/** New ids are raised unless arena is in front, where they are only marked seen; ids that left are closed. */
export function plan(raised: ReadonlySet<string>, now: Item[], arenaInFront: boolean) {
  const ids = new Set(now.map((i) => i.id))
  return {
    raise: arenaInFront ? [] : now.filter((i) => !raised.has(i.id)),
    seen: now.map((i) => i.id).filter((id) => !raised.has(id)),
    close: [...raised].filter((id) => !ids.has(id)),
  }
}

/** The ids saved in needs-raised.json; anything corrupt or not a list of strings yields only what is valid. */
export function parseRaised(text: string): string[] {
  try {
    const ids: unknown = JSON.parse(text)
    return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === "string") : []
  } catch { return [] }
}

export const HINT = "x-needs-you"


/** notify-send, blocking until an action is chosen: `default` is the click on the body, `aN` the Nth action with an argv. */
export function noticeArgv(i: Item, n: number): string[] {
  const acts = i.actions.filter((a) => a.argv)
  return [
    "notify-send", "-a", "arena", "-h", `string:${HINT}:${i.id}`, "-A", "default=open",
    ...acts.flatMap((a, k) => ["-A", `a${k}=${a.label}`]),
    `▲ ${n} need you`, i.text,
  ]
}

/** The argv an action name printed by notify-send stands for; null for `default` (open) or none. */
export const chosen = (i: Item, name: string): string[] | null => {
  const k = /^a(\d+)$/.exec(name.trim())
  return k ? (i.actions.filter((a) => a.argv)[Number(k[1])]?.argv ?? null) : null
}
