export type Waiting = { kind: string; ticket: number | null; text: string }
export type Board = {
  auto: { on: boolean; cap: number; repo_caps?: Record<string, number> }
  tickets: { id: number; status: string; repo: string; claimed_by: string | null }[]
  plan: { next: { ticket: number }[] }
  needs_you: Waiting[]
}


export const parseBoard = (text: string): Board | null => {
  try {
    const b = JSON.parse(text)
    return Array.isArray(b?.tickets) && Array.isArray(b?.plan?.next) && Array.isArray(b?.needs_you) && typeof b?.auto?.on === 'boolean' ? b : null
  } catch {
    return null
  }
}

const PROPOSAL = /\bproposal\s+#?\d+/i
const ITEM = /^\s*(?:try|answer|look at)\b[^#]*#(\d+)/i

/** The board item a line names: a ticket's card, the inbox for a proposal or ask; null for a plain reply. */
export const item = (text: string): { argv: string[]; ticket: number | null } | null => {
  if (PROPOSAL.test(text)) return { argv: ['arena', 'inbox'], ticket: null }
  const id = ITEM.exec(text)?.[1]
  return id === undefined ? null : { argv: ['arena', 'board', id], ticket: Number(id) }
}

const START = /^\s*(?:start|drive|work(?: on)?)\s+#?(\d+)\b/i

/** A suggestion that starts a ticket is kept only when that ticket is a free todo that auto will not start itself and its repo has room. */
export const startable = (text: string, b: Board): boolean => {
  const named = item(text)?.ticket
  if (named != null) return b.tickets.some(c => c.id === named && c.status !== 'done')
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
