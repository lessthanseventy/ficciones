// The backdrop rotation's pile: ambients and xscreensaver hacks together, so an ambient and a hack
// of one name (maze, pipes, flow) stay two entries.
export type Turn = { hack: boolean; name: string }

/** A random entry of the pile not in `showing`; with nothing else left, any entry; null when the
 * pile is empty. */
export function pickTurn(ambients: string[], hacks: string[], showing: Turn[], random = Math.random): Turn | null {
  const pile = [...ambients.map((name) => ({ hack: false, name })), ...hacks.map((name) => ({ hack: true, name }))]
  const fresh = pile.filter((t) => !showing.some((s) => s.hack === t.hack && s.name === t.name))
  const from = fresh.length ? fresh : pile
  return from[Math.floor(random() * from.length)] ?? null
}
