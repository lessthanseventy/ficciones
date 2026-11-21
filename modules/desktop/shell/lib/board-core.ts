// The pure half of lib/board.ts: babylon's board file, read for the office rail.

export type Ask = { id: number; question: string; options: string[] }
export type Card = { id: number; status: string; title: string; repo: string; claimed_by: string | null; ask: Ask | null }
/** `socket` is the tmux server every `claimed_by` is a pane of; null when the board does not say */
export type Board = { tickets: Card[]; auto: { on: boolean; cap: number; working: number }; hold: boolean; socket: string | null }

export function parse(text: string): Board | null {
  try {
    const b = JSON.parse(text)
    return Array.isArray(b?.tickets) && typeof b?.auto?.on === "boolean"
      ? { tickets: b.tickets, auto: b.auto, hold: b.hold === true, socket: typeof b.socket === "string" ? b.socket : null }
      : null
  } catch { return null }
}

/** the cards with a question open for you */
export const asking = (b: Board | null): Card[] => (b?.tickets ?? []).filter((t) => t.ask)

/** the ticket a tmux pane's Claude holds: the one it works on before one it has handed in. Pane ids repeat across tmux servers. */
export function held(b: Board | null, at: { socket: string; pane: string }): Card | null {
  if (!b || !at.pane || (b.socket !== null && b.socket !== at.socket)) return null
  const open = b.tickets.filter((t) => t.claimed_by === at.pane && (t.status === "doing" || t.status === "review"))
  return open.find((t) => t.status === "doing") ?? open[0] ?? null
}

export function boardLine(b: Board | null): string {
  if (!b) return "no board"
  const n = (status: string) => b.tickets.filter((t) => t.status === status).length
  return [`doing ${n("doing")}`, `review ${n("review")}`, `asks ${asking(b).length}`, b.auto.on ? `auto ${b.auto.working}/${b.auto.cap}` : "auto off", b.hold ? "hold on" : "hold off"].join(" · ")
}
