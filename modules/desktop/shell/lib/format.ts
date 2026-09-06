export const pct = (p: number) => `${Math.round(p * 100)}%`

/** 4-cell text meter: `▮▮▯▯` — the rail is too narrow for words like "medium". */
export function meter(frac: number, cells = 4): string {
  const on = Math.round(Math.max(0, Math.min(1, frac)) * cells)
  return "▮".repeat(on) + "▯".repeat(cells - on)
}

/**
 * Braille sparkline: two samples per cell, four dot-rows per column, so `width` cells show
 * `2*width` samples of 0..1. The last sample is rightmost. Short histories pad on the left.
 */
export function spark(values: number[], width: number): string {
  const n = width * 2
  const v = values.slice(-n)
  const pad = new Array(Math.max(0, n - v.length)).fill(-1)
  const s = [...pad, ...v]
  const L = [0x40, 0x04, 0x02, 0x01] // left column, bottom→top
  const R = [0x80, 0x20, 0x10, 0x08]
  // a real sample always draws at least the baseline dot, so idle and no-data differ; each
  // further row is a quarter (25/50/75), not a rounding — 18% and 36% must not look alike
  const lvl = (x: number) => (x < 0 ? 0 : Math.min(4, 1 + Math.floor(Math.min(0.999, x) * 4)))
  let out = ""
  for (let i = 0; i < n; i += 2) {
    let bits = 0
    for (let k = 0; k < lvl(s[i]); k++) bits |= L[k]
    for (let k = 0; k < lvl(s[i + 1]); k++) bits |= R[k]
    out += String.fromCodePoint(0x2800 + bits)
  }
  return out
}
