// Funes on the launcher: it remembers everything run — apps, shell lines, files, sums — and
// ranks by recency and frequency, so what you reach for is on top and an empty prompt shows
// what you reached for last. One JSON file in the state dir; frecency = count decayed by age
// (halves every four days). Funes, of course, forgot nothing, which was his trouble: entries
// unused for ninety days are let go.
import GLib from "gi://GLib?version=2.0"

export type Memory = { key: string; mode: string; title: string; sub?: string; count: number; last: number }

const FILE = `${GLib.get_user_state_dir()}/astal-shell/funes.json`
const HALF_LIFE_MS = 4 * 86_400_000
const FORGET_MS = 90 * 86_400_000
let mem: Record<string, Memory> = {}

try {
  const [ok, bytes] = GLib.file_get_contents(FILE)
  if (ok) mem = JSON.parse(new TextDecoder().decode(bytes))
} catch { /* first run */ }

function save() {
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(FILE), 0o755)
    GLib.file_set_contents(FILE, JSON.stringify(mem))
  } catch (e) { console.error("funes:", String(e)) }
}

export function remember(m: Omit<Memory, "count" | "last">) {
  const id = `${m.mode}:${m.key}`
  const prev = mem[id]
  mem[id] = { ...m, count: (prev?.count ?? 0) + 1, last: Date.now() }
  const cutoff = Date.now() - FORGET_MS
  for (const k of Object.keys(mem)) if (mem[k].last < cutoff) delete mem[k]
  save()
}

export function score(mode: string, key: string): number {
  const m = mem[`${mode}:${key}`]
  if (!m) return 0
  return m.count * Math.pow(0.5, (Date.now() - m.last) / HALF_LIFE_MS)
}

/** The most-reached-for, across modes, for the empty prompt. */
export function recent(n: number, modes?: string[]): Memory[] {
  return Object.values(mem)
    .filter((m) => !modes || modes.includes(m.mode))
    .sort((a, b) => score(b.mode, b.key) - score(a.mode, a.key))
    .slice(0, n)
}

export const times = (mode: string, key: string) => mem[`${mode}:${key}`]?.count ?? 0
