// A braille dot canvas: 2×4 dots per character cell, so a W×H cell grid holds 2W×4H dots.
// Draw with plot(); read the frame as lines of text for a monospace label.
export class CharGrid {
  readonly cols: number
  readonly rows: number
  private dots: Uint8Array
  constructor(cols: number, rows: number) {
    this.cols = cols; this.rows = rows
    this.dots = new Uint8Array(cols * rows)
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
  plot(x: number, y: number) {
    const cx = Math.floor(x / 2), cy = Math.floor(y / 4)
    if (cx < 0 || cy < 0 || cx >= this.cols || cy >= this.rows) return
    const dx = Math.floor(x) & 1, dy = Math.floor(y) & 3
    // braille bit layout: left column 1,2,3,7 ; right column 4,5,6,8
    const bit = dx === 0 ? [0x01, 0x02, 0x04, 0x40][dy] : [0x08, 0x10, 0x20, 0x80][dy]
    this.dots[cy * this.cols + cx] |= bit
  }
  lines(): string[] {
    const out: string[] = []
    for (let r = 0; r < this.rows; r++) {
      let s = ""
      for (let c = 0; c < this.cols; c++) s += String.fromCodePoint(0x2800 + this.dots[r * this.cols + c])
      out.push(s)
    }
    return out
  }
}
