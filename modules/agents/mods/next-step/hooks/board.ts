export type Waiting = { kind: string; ticket: number | null; text: string }
export type Board = {
  auto: { on: boolean; cap: number; repo_caps?: Record<string, number> }
  tickets: { id: number; status: string; repo: string; claimed_by: string | null }[]
  plan: { next: { ticket: number }[] }
  needs_you: Waiting[]
}

// The human's own word for what a needs_you row asks of them.
const VERB: Record<string, string> = { try: 'try', ask: 'answer', human: 'answer', look: 'look at', proposal: 'answer', sendback: 'look at' }

export const parseBoard = (text: string): Board | null => {
  try {
    const b = JSON.parse(text)
    return Array.isArray(b?.tickets) && Array.isArray(b?.plan?.next) && Array.isArray(b?.needs_you) && typeof b?.auto?.on === 'boolean' ? b : null
  } catch {
    return null
  }
}

/** What waits on the human, as a button label; null when nothing does. */
export const waiting = (b: Board): { label: string; ticket: number | null } | null => {
  const top = b.needs_you[0]
  if (top === undefined) return null
  const verb = VERB[top.kind] ?? 'open'
  return { label: top.ticket === null ? `${verb}: ${top.text}` : `${verb} #${top.ticket}`, ticket: top.ticket }
}

const START = /^\s*(?:start|drive|work(?: on)?)\s+#?(\d+)\b/i

/** A suggestion that starts a ticket is kept only when that ticket is a free todo that auto will not start itself and its repo has room. */
export const startable = (text: string, b: Board): boolean => {
  const id = START.exec(text)?.[1]
  if (id === undefined) return true
  const t = b.tickets.find(c => c.id === Number(id))
  if (t === undefined || t.status !== 'todo' || t.claimed_by !== null) return false
  if (b.auto.on && b.plan.next.some(n => n.ticket === t.id)) return false
  const busy = b.tickets.filter(c => c.repo === t.repo && c.status === 'doing').length
  return busy < (b.auto.repo_caps?.[t.repo] ?? b.auto.cap)
}
