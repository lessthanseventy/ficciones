export type Waiting = { kind: string; ticket: number | null; text: string }
export type Board = {
  auto: { on: boolean; cap: number; repo_caps?: Record<string, number> }
  tickets: { id: number; status: string; repo: string; claimed_by: string | null; ask?: unknown }[]
  proposals: { id: number }[]
  plan: { next: { ticket: number }[] }
  needs_you: Waiting[]
}


export const parseBoard = (text: string): Board | null => {
  try {
    const b = JSON.parse(text)
    return Array.isArray(b?.tickets) && Array.isArray(b?.plan?.next) && Array.isArray(b?.needs_you) && Array.isArray(b?.proposals) && typeof b?.auto?.on === 'boolean' ? b : null
  } catch {
    return null
  }
}

const PROPOSAL = /^\s*go on proposal\s+(\d+)\s*$/i
const ITEM = /^\s*(try|answer|look at)\s+#(\d+)(?:'s send-back)?\s*$/i

type Item = { argv: string[]; ticket: number | null; proposal: number | null; answer: boolean }

/** The board item a line names, only in its exact whole-line forms: `try #N`, `answer #N`, `go on proposal N`, `look at #N's send-back`. Anything else is a reply: null. */
export const item = (text: string): Item | null => {
  const proposal = PROPOSAL.exec(text)?.[1]
  if (proposal !== undefined) return { argv: ['arena', 'inbox'], ticket: null, proposal: Number(proposal), answer: false }
  const [, verb, id] = ITEM.exec(text) ?? []
  if (id === undefined) return null
  if (/^look at$/i.test(verb) !== /send-back\s*$/i.test(text)) return null
  return { argv: ['arena', 'board', id], ticket: Number(id), proposal: null, answer: /^answer$/i.test(verb) }
}

const START = /^\s*(?:start|drive|work(?: on)?)\s+#?(\d+)\b/i

/** A suggestion that starts a ticket is kept only when that ticket is a free todo that auto will not start itself and its repo has room. */
export const startable = (text: string, b: Board): boolean => {
  const named = item(text)
  if (named?.proposal != null) return b.proposals.some(p => p.id === named.proposal)
  if (named?.ticket != null) return b.tickets.some(c => c.id === named.ticket && c.status !== 'done' && (!named.answer || c.ask != null))
  const id = START.exec(text)?.[1]
  if (id === undefined) return true
  const t = b.tickets.find(c => c.id === Number(id))
  if (t === undefined || t.status !== 'todo' || t.claimed_by !== null) return false
  if (b.auto.on && b.plan.next.some(n => n.ticket === t.id)) return false
  const busy = b.tickets.filter(c => c.repo === t.repo && c.status === 'doing').length
  return busy < (b.auto.repo_caps?.[t.repo] ?? b.auto.cap)
}

const NEXT_LINE = /^[ \t]*next:[ \t]*(.*?)[ \t]*$/gim

/** The move named by the last `next: <move>` line of a reply; null when there is none or it says `none`. */
export const nextLine = (reply: string): string | null => {
  const move = [...reply.matchAll(NEXT_LINE)].at(-1)?.[1] ?? ''
  return move === '' || /^none\.?$/i.test(move) ? null : move
}
