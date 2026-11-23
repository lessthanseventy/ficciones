// The pure half of lib/board.ts: babylon's board file, read for the office rail.

/** `argv` is the command that does it; null when a surface must ask for more first (words, a pick) */
export type Action = { key: string; label: string; argv: string[] | null }
export type Item = { id: string; kind: string; ticket: number | null; repo: string; text: string; actions: Action[] }

/** Items with an id and a text, one per such entry, so the count is the board's; an entry with no action list has no actions. The rest of `needs_you` is not ours to guess at. */
export function items(raw: unknown): Item[] {
  if (!Array.isArray(raw)) return []
  return raw.filter(
    (i) => typeof i?.id === "string" && typeof i?.text === "string",
  ).map((i) => ({
    id: i.id, kind: String(i.kind), ticket: typeof i.ticket === "number" ? i.ticket : null, repo: String(i.repo ?? ""), text: i.text,
    actions: (Array.isArray(i.actions) ? i.actions : []).filter((a: Action) => typeof a?.label === "string").map((a: Action) => ({
      key: String(a.key), label: a.label, argv: Array.isArray(a.argv) ? a.argv.map(String) : null,
    })),
  }))
}

export type Ask = { id: number; question: string; options: string[] }
export type Card = { id: number; status: string; title: string; repo: string; claimed_by: string | null; ask: Ask | null; stage?: string | null; blocked_by?: number[] }
/** `socket` is the tmux server every `claimed_by` is a pane of; null when the board does not say */
export type Board = { tickets: Card[]; auto: { on: boolean; cap: number; working: number; repo_caps?: Record<string, number> }; hold: boolean; socket: string | null; needsYou: Item[]; orchestrator: { on: boolean; running: boolean } | null }

export function parse(text: string): Board | null {
  try {
    const b = JSON.parse(text)
    return Array.isArray(b?.tickets) && typeof b?.auto?.on === "boolean"
      ? { tickets: b.tickets, auto: b.auto, hold: b.hold === true, socket: typeof b.socket === "string" ? b.socket : null, needsYou: items(b.needs_you), orchestrator: typeof b.orchestrator?.running === "boolean" ? { on: b.orchestrator.on !== false, running: b.orchestrator.running } : null }
      : null
  } catch { return null }
}

/** the cards with a question open for you */
export const asking = (b: Board | null): Card[] => (b?.tickets ?? []).filter((t) => t.ask)
