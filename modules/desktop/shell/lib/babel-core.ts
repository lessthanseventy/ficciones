// The pure half of lib/babel.ts: the sentence a librarian finds among the noise.

/** one page in `1 / FOUND_ODDS` holds a sentence that means something */
export const FOUND_ODDS = 0.001
export const FOUND = [
  "somewhere in these rooms is the book of you",
  "the librarian who read this page went home happy",
  "every page is true in some other library",
  "you were looking for this one",
  "a hexagon further on, a man is reading this too",
  "the catalogue of catalogues is on the next shelf",
]

/** a found sentence wrapped to `width`, or null on the usual page */
export function foundLines(width: number, rng: () => number): string[] | null {
  if (rng() >= FOUND_ODDS) return null
  const out: string[] = []
  for (const word of (FOUND[Math.floor(rng() * FOUND.length)] ?? "").split(" ")) {
    if (out.length && `${out.at(-1)} ${word}`.length <= width) out[out.length - 1] += ` ${word}`
    else out.push(word.slice(0, width))
  }
  return out
}
