export type Run = { t: string; c?: string; b?: string; bold?: true; dim?: true; it?: true; u?: true; inv?: true }

const ANSI = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']

const hex = (r: number, g: number, b: number) =>
  '#' + [r, g, b].map(n => n.toString(16).padStart(2, '0')).join('')

const color256 = (n: number): string => {
  if (n < 8) return ANSI[n]!
  if (n < 16) return `${ANSI[n - 8]}Bright`
  if (n >= 232) {
    const v = 8 + (n - 232) * 10
    return hex(v, v, v)
  }
  const i = n - 16
  const level = (d: number) => (d === 0 ? 0 : 55 + d * 40)
  return hex(level(Math.floor(i / 36)), level(Math.floor(i / 6) % 6), level(i % 6))
}

type Style = Omit<Run, 't'>

const applySgr = (style: Style, params: number[]): Style => {
  let s = style
  for (let i = 0; i < params.length; i++) {
    const p = params[i] ?? 0
    if (p === 0) s = {}
    else if (p === 1) s = { ...s, bold: true }
    else if (p === 2) s = { ...s, dim: true }
    else if (p === 3) s = { ...s, it: true }
    else if (p === 4) s = { ...s, u: true }
    else if (p === 7) s = { ...s, inv: true }
    else if (p === 22) { const { bold, dim, ...rest } = s; s = rest }
    else if (p === 23) { const { it, ...rest } = s; s = rest }
    else if (p === 24) { const { u, ...rest } = s; s = rest }
    else if (p === 27) { const { inv, ...rest } = s; s = rest }
    else if (p >= 30 && p <= 37) s = { ...s, c: color256(p - 30) }
    else if (p >= 40 && p <= 47) s = { ...s, b: color256(p - 40) }
    else if (p >= 90 && p <= 97) s = { ...s, c: color256(p - 90 + 8) }
    else if (p >= 100 && p <= 107) s = { ...s, b: color256(p - 100 + 8) }
    else if (p === 39) { const { c, ...rest } = s; s = rest }
    else if (p === 49) { const { b, ...rest } = s; s = rest }
    else if (p === 38 || p === 48) {
      const key = p === 38 ? 'c' : 'b'
      if (params[i + 1] === 5) {
        s = { ...s, [key]: color256(params[i + 2] ?? 0) }
        i += 2
      } else if (params[i + 1] === 2) {
        s = { ...s, [key]: hex(params[i + 2] ?? 0, params[i + 3] ?? 0, params[i + 4] ?? 0) }
        i += 4
      }
    }
  }
  return s
}

const pushText = (runs: Run[], style: Style, text: string) => {
  if (text === '') return
  const last = runs[runs.length - 1]
  if (last && JSON.stringify({ ...last, t: '' }) === JSON.stringify({ ...style, t: '' })) last.t += text
  else runs.push({ ...style, t: text })
}

// tmux's `capture-pane -e -p` carries SGR across lines, so style is threaded through every row.
export const parseFrame = (capture: string, rows: number, cursor?: { x: number; y: number }): Run[][] => {
  const lines = capture.split('\n').slice(0, rows)
  let style: Style = {}
  return lines.map((line, y) => {
    const runs: Run[] = []
    let col = 0
    const emit = (text: string) => {
      if (cursor && y === cursor.y && col <= cursor.x && cursor.x < col + [...text].length) {
        const chars = [...text]
        const at = cursor.x - col
        pushText(runs, style, chars.slice(0, at).join(''))
        pushText(runs, { ...style, inv: true }, chars[at] ?? ' ')
        pushText(runs, style, chars.slice(at + 1).join(''))
      } else pushText(runs, style, text)
      col += [...text].length
    }
    for (const part of line.split(/(\x1b\[[0-9;:]*[A-Za-z])/)) {
      const sgr = /^\x1b\[([0-9;:]*)m$/.exec(part)
      if (sgr) style = applySgr(style, (sgr[1] ?? '').split(/[;:]/).map(n => Number(n) || 0))
      else if (!part.startsWith('\x1b[')) emit(part)
    }
    if (cursor && y === cursor.y && col <= cursor.x) {
      pushText(runs, style, ' '.repeat(cursor.x - col))
      pushText(runs, { ...style, inv: true }, ' ')
    }
    return runs
  })
}

// A Client's props past 100000 characters unmount it, so an oversized frame loses its styling instead.
const FRAME_LIMIT = 90_000

export const fitFrame = (rows: Run[][]): Run[][] =>
  JSON.stringify(rows).length <= FRAME_LIMIT ? rows : rows.map(row => [{ t: row.map(r => r.t).join('') }])

const NAMED: Record<string, string> = {
  up: 'Up', down: 'Down', left: 'Left', right: 'Right', return: 'Enter', enter: 'Enter', tab: 'Tab',
  backspace: 'BSpace', delete: 'DC', pageup: 'PPage', pagedown: 'NPage', home: 'Home', end: 'End', space: 'Space',
}

export type Key = { key: string; ctrl?: true; shift?: true; meta?: true }

export const tmuxKey = ({ key, ctrl, shift, meta }: Key): string => {
  if (key === 'tab' && shift) return 'BTab'
  const name = NAMED[key]
  // tmux reads a trailing `;` in an argument as its command separator.
  const base = name ?? (key === ';' ? '\;' : key)
  const shifted = shift && name ? `S-${base}` : base
  return `${meta ? 'M-' : ''}${ctrl ? 'C-' : ''}${shifted}`
}
