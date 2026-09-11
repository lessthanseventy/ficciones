// A braille dot canvas: 2×4 dots per character cell, so a W×H cell grid holds 2W×4H dots.
// Each cell also carries a hue index; lines() emits Pango markup with a span per hue run.
import { PALETTE, HUES, type Hue } from "./palette"

// braille bit layout: left column 1,2,3,7 ; right column 4,5,6,8. Module constants: plot() runs
// ~17k times a step under life, and an array literal there was allocated per call.
const LEFT = [0x01, 0x02, 0x04, 0x40], RIGHT = [0x08, 0x10, 0x20, 0x80]

export class CharGrid {
  readonly cols: number
  readonly rows: number
  readonly dots: Uint8Array
  readonly hue: Uint8Array
  /** rotates the hue ring, so "the same" colour index drifts through the palette */
  shift = 0
  constructor(cols: number, rows: number) {
    this.cols = cols; this.rows = rows
    this.dots = new Uint8Array(cols * rows)
    this.hue = new Uint8Array(cols * rows)
  }
  clear() { this.dots.fill(0) }
  /** fade every cell's dots out at random — a phosphor decay */
  decay(p: number) {
    for (let i = 0; i < this.dots.length; i++) {
      let b = this.dots[i]
      if (!b) continue
      for (let k = 0; k < 8; k++) if (b & (1 << k) && Math.random() < p) b &= ~(1 << k)
      this.dots[i] = b
    }
  }
  plot(x: number, y: number, hue = 0) {
    const cx = Math.floor(x / 2), cy = Math.floor(y / 4)
    if (cx < 0 || cy < 0 || cx >= this.cols || cy >= this.rows) return
    const dx = Math.floor(x) & 1, dy = Math.floor(y) & 3
    const bit = (dx === 0 ? LEFT : RIGHT)[dy]
    const i = cy * this.cols + cx
    this.dots[i] |= bit
    this.hue[i] = hue
  }
  colour(h: number): string {
    return PALETTE[HUES[(h + this.shift) % HUES.length] as Hue]
  }
  /** one markup string per row: runs of equal hue share a span, blanks stay plain */
  lines(): string[] {
    const out: string[] = []
    for (let r = 0; r < this.rows; r++) {
      let s = "", run = "", runHue = -1
      const flush = () => { if (run) s += runHue < 0 ? run : `<span foreground="${this.colour(runHue)}">${run}</span>`; run = "" }
      for (let c = 0; c < this.cols; c++) {
        const i = r * this.cols + c
        const d = this.dots[i]
        const h = d ? this.hue[i] : -1
        if (h !== runHue) { flush(); runHue = h }
        run += String.fromCodePoint(0x2800 + d)
      }
      flush()
      out.push(s)
    }
    return out
  }
}
