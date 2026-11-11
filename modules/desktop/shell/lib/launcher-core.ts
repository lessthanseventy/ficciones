// How the launcher orders apps for what was typed: by how the text matches first, by use second.

export type Candidate = { name: string; exec: string; words: string[] }

const wordStarts = (s: string, q: string) => s.split(/[^\p{L}\p{N}]+/u).some((w) => w.startsWith(q))

/** The typed letters in order with gaps, from the first letter: a looser start matches most of the list. */
function inOrder(s: string, q: string): boolean {
  if (s[0] !== q[0]) return false
  let i = 0
  for (const ch of s) if (ch === q[i]) i++
  return i === q.length
}

/** 0 is no match; a higher number is a closer one. */
export function match(query: string, c: Candidate): number {
  const q = query.trim().toLowerCase()
  if (!q) return 0
  const name = c.name.toLowerCase()
  if (name.startsWith(q)) return 6
  if (wordStarts(name, q)) return 5
  if (c.exec.toLowerCase().startsWith(q)) return 4
  if (name.includes(q)) return 3
  if (c.words.some((w) => wordStarts(w.toLowerCase(), q))) return 2
  if (inOrder(name, q)) return 1
  return 0
}

/** The items that match, closest first; `used` (frecency) orders those that match equally well. */
export function order<T>(query: string, items: T[], candidate: (t: T) => Candidate, used: (t: T) => number): T[] {
  return items
    .map((t) => { const c = candidate(t); return { t, m: match(query, c), u: used(t), name: c.name } })
    .filter((x) => x.m > 0)
    .sort((a, b) => b.m - a.m || b.u - a.u || a.name.length - b.name.length || a.name.localeCompare(b.name))
    .map((x) => x.t)
}
