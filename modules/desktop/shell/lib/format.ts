export const pct = (p: number) => `${Math.round(p * 100)}%`

/** 4-cell text meter: `▮▮▯▯` — the rail is too narrow for words like "medium". */
export function meter(frac: number, cells = 4): string {
  const on = Math.round(Math.max(0, Math.min(1, frac)) * cells)
  return "▮".repeat(on) + "▯".repeat(cells - on)
}
