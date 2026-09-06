// The Library of Babel: hexagonal galleries of text drifting up the screen, a fragment of a real
// book in each cell. The books are public-domain texts from Project Gutenberg, fetched once into
// the cache; until they land (or offline) the cells hold what most of the Library holds —
// runs of the twenty-five orthographic symbols. Rendered as rows of Pango markup for the
// backdrop's label grid (lib/ambient.ts hands it the canvas size and the tick).
import GLib from "gi://GLib?version=2.0"
import Gio from "gi://Gio?version=2.0"
import { execAsync } from "ags/process"
import { PALETTE, type Hue } from "./palette"

const DIR = `${GLib.get_user_cache_dir()}/astal-shell/babel`
// Gutenberg ids: Moby-Dick, Alice, Don Quixote, the Divine Comedy (Longfellow), Pride and
// Prejudice, the Odyssey (Butler), Frankenstein, Dracula
const BOOKS = [2701, 11, 996, 8800, 1342, 1727, 84, 345]
const SYMBOLS = "abcdefghijklmnopqrstuv ., " // twenty-two letters, the space, the period, the comma

let books: string[] = []
let fetching = false

function loadBooks() {
  books = []
  try {
    const e = Gio.File.new_for_path(DIR).enumerate_children("standard::name", 0, null)
    let i: Gio.FileInfo | null
    while ((i = e.next_file(null))) {
      const [ok, bytes] = GLib.file_get_contents(`${DIR}/${i.get_name()}`)
      if (!ok) continue
      let t = new TextDecoder().decode(bytes)
      // strip the Gutenberg boilerplate at both ends
      const a = t.indexOf("*** START"), b = t.lastIndexOf("*** END")
      if (a > 0) t = t.slice(t.indexOf("\n", a) + 1)
      if (b > 0) t = t.slice(0, t.lastIndexOf("\n", t.indexOf("*** END")))
      t = t.replace(/\r/g, "").replace(/[ \t]+/g, " ").replace(/\n{2,}/g, "\n\n")
      if (t.length > 10_000) books.push(t)
    }
  } catch { /* nothing yet */ }
}

/** Fetch the books once, in the background; the grid picks them up on its next cell. */
export function ensureBooks() {
  loadBooks()
  if (books.length >= BOOKS.length || fetching) return
  fetching = true
  GLib.mkdir_with_parents(DIR, 0o755)
  Promise.all(BOOKS.map((id) => {
    const f = `${DIR}/pg${id}.txt`
    if (Gio.File.new_for_path(f).query_exists(null)) return Promise.resolve()
    return execAsync(["curl", "-fsSL", "--max-time", "60", "-o", f, `https://www.gutenberg.org/cache/epub/${id}/pg${id}.txt`]).then(() => void 0).catch(() => {})
  })).then(() => { loadBooks(); fetching = false })
}

/** A deterministic PRNG per cell, so a cell keeps its text while it drifts. */
function rng(seed: number) {
  let s = (seed * 2654435761) >>> 0 || 1
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296 }
}

const symbols = (r: () => number, n: number) => Array.from({ length: n }, () => SYMBOLS[Math.floor(r() * SYMBOLS.length)]).join("")

/**
 * `n` lines of at most `w` chars: a fragment of a book with the Library's symbols sprinkled
 * through it (a word in six goes to letters — Andrew, 2026-09-05: "sprinkle in the symbols with
 * the text"); one cell in seven is pure symbols, as most of the Library is.
 */
function fragment(seed: number, w: number, n: number): { lines: string[]; real: boolean } {
  const r = rng(seed)
  if (books.length && r() > 1 / 7) {
    const book = books[Math.floor(r() * books.length)]
    const at = Math.floor(r() * (book.length - 4000))
    const start = book.indexOf(" ", at) + 1
    const words = book.slice(start, start + 4000).replace(/\n/g, " ").split(/\s+/).filter(Boolean)
      .map((word) => (r() < 1 / 6 ? symbols(r, word.length).replace(/ /g, ".") : word))
    const lines: string[] = []
    let cur = ""
    for (const word of words) {
      if (lines.length >= n) break
      if ((cur + " " + word).trim().length > w) { lines.push(cur.trim()); cur = word }
      else cur = (cur + " " + word).trim()
    }
    if (lines.length < n && cur) lines.push(cur)
    return { lines: lines.slice(0, n), real: true }
  }
  return { lines: Array.from({ length: n }, () => symbols(r, w)), real: false }
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

/** The honeycomb. Cell (i, j) is fixed in the lattice; the viewport scrolls over it. */
export class Babel {
  readonly W = 30 // cell width in chars
  readonly H = 12 // cell height in rows
  scroll = 0      // rows, fractional
  speed = 0.06    // rows per tick — a slow drift
  private cache = new Map<string, { lines: string[]; real: boolean; hue: Hue | null }>()
  constructor(readonly cols: number, readonly rows: number) {}

  private cell(i: number, j: number) {
    const k = `${i}:${j}`
    let c = this.cache.get(k)
    if (!c) {
      const seed = (i * 73856093) ^ (j * 19349663) ^ 0x9e3779b9
      const f = fragment(seed, this.W - 10, this.H - 4)
      // most cells read in amber; every fifth or so in another of the Library's inks
      const r = rng(seed + 7)()
      const hue: Hue | null = r < 0.8 ? null : (["green", "cyan", "pink", "lilac"] as Hue[])[Math.floor((r - 0.8) * 20) % 4]
      c = { ...f, hue }
      this.cache.set(k, c)
      if (this.cache.size > 400) this.cache.delete(this.cache.keys().next().value!)
    }
    return c
  }

  step() { this.scroll += this.speed }

  /** Rows of markup. Hex edges dim; text amber (plain), or a cell's own hue. */
  lines(): string[] {
    const { W, H, cols, rows } = this
    const ch: string[][] = Array.from({ length: rows }, () => new Array(cols).fill(" "))
    const hue: (string | null)[][] = Array.from({ length: rows }, () => new Array(cols).fill(null))
    const put = (x: number, y: number, s: string, h: string | null) => {
      if (y < 0 || y >= rows) return
      for (let k = 0; k < s.length; k++) { const xx = x + k; if (xx >= 0 && xx < cols) { ch[y][xx] = s[k]; hue[y][xx] = h } }
    }
    // flat-top hexes interlock (one shared wall) at a pitch of the width less a slanted side
    // less one: the lower slant starts a column inside the upper one's end
    const pitchX = W - H / 2 - 1, pitchY = H
    const off = Math.floor(this.scroll)
    const half = H / 2
    // whole columns only, centred: a hex cut at the screen's edge reads as a mistake
    const nCols = Math.max(1, Math.floor((cols - W) / pitchX) + 1)
    const margin = Math.floor((cols - ((nCols - 1) * pitchX + W)) / 2)
    for (let i = 0; i < nCols; i++) {
      const yShift = i % 2 ? half : 0
      const j0 = Math.floor((off - yShift) / pitchY) - 1
      for (let j = j0; (j * pitchY + yShift - off) < rows + H; j++) {
        const x0 = margin + i * pitchX, y0 = j * pitchY + yShift - off
        const c = this.cell(i, j)
        const dim = PALETTE.dim
        const ink = c.hue ? PALETTE[c.hue] : null
        // flat-top hexagon, W wide, H tall: a run of underscores, slanted sides, underscores
        put(x0 + half, y0, "_".repeat(W - H), dim)
        for (let r = 1; r < half; r++) { put(x0 + half - r, y0 + r, "/", dim); put(x0 + W - 1 - half + r, y0 + r, "\\", dim) }
        for (let r = 0; r < half; r++) { put(x0 + r, y0 + half + r, "\\", dim); put(x0 + W - 1 - r, y0 + half + r, "/", dim) }
        put(x0 + half, y0 + H - 1, "_".repeat(W - H), dim)
        // the fragment, centred, one line per interior row
        const tw = W - 10
        c.lines.forEach((l, k) => { const y = y0 + 2 + k; if (y > y0 && y < y0 + H - 1) put(x0 + 5 + Math.floor((tw - l.length) / 2), y, l, ink) })
      }
    }
    // runs of equal hue share a span
    return ch.map((row, y) => {
      let s = "", run = "", runHue: string | null = null
      const flush = () => { if (run) s += runHue ? `<span foreground="${runHue}">${esc(run)}</span>` : esc(run); run = "" }
      for (let x = 0; x < cols; x++) {
        const h: string | null = row[x] === " " ? runHue : hue[y][x]
        if (h !== runHue) { flush(); runHue = h }
        run += row[x]
      }
      flush()
      return s
    })
  }
}
