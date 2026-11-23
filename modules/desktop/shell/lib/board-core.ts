// The pure half of lib/board.ts: babylon's board file, read for the office rail.

export type Ask = { id: number; question: string; options: string[] }
export type Card = { id: number; status: string; title: string; repo: string; claimed_by: string | null; ask: Ask | null; stage?: string | null; blocked_by?: number[] }
/** `socket` is the tmux server every `claimed_by` is a pane of; null when the board does not say */
export type Board = { tickets: Card[]; auto: { on: boolean; cap: number; working: number }; hold: boolean; socket: string | null; proposals: number; orchestrator: { on: boolean; running: boolean } | null }

export function parse(text: string): Board | null {
  try {
    const b = JSON.parse(text)
    return Array.isArray(b?.tickets) && typeof b?.auto?.on === "boolean"
      ? { tickets: b.tickets, auto: b.auto, hold: b.hold === true, socket: typeof b.socket === "string" ? b.socket : null, proposals: Array.isArray(b.proposals) ? b.proposals.length : 0, orchestrator: typeof b.orchestrator?.running === "boolean" ? { on: b.orchestrator.on !== false, running: b.orchestrator.running } : null }
      : null
  } catch { return null }
}

/** the cards with a question open for you */
export const asking = (b: Board | null): Card[] => (b?.tickets ?? []).filter((t) => t.ask)
