export type File = { path: string; isUntracked: boolean }
export type DiffLine = { text: string; hunk: number }
export type Run = { t: string; c?: string; b?: string; bold?: true; dim?: true; it?: true; u?: true }

export const parseStatus = (z: string): File[] => {
  const entries = z.split('\0')
  const files: File[] = []
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i]!
    if (entry.length <= 3) continue
    const [x, y] = [entry[0]!, entry[1]!]
    files.push({ path: entry.slice(3), isUntracked: x === '?' })
    // -z puts a rename's origin in an entry of its own.
    if (x === 'R' || x === 'C' || y === 'R' || y === 'C') i++
  }
  return files
}

export const splitDiff = (diff: string): Map<string, string> => {
  const byPath = new Map<string, string>()
  for (const chunk of diff.split(/^(?=diff --git )/m)) {
    const name = /^\+\+\+ b\/(.*)$/m.exec(chunk)?.[1] ?? /^--- a\/(.*)$/m.exec(chunk)?.[1]
    if (name) byPath.set(name.replace(/\t$/, ''), chunk)
  }
  return byPath
}

export const parseDiff = (diff: string): DiffLine[] => {
  const lines: DiffLine[] = []
  let hunk = -1
  for (const text of diff.split('\n')) {
    if (text.startsWith('@@ ')) hunk++
    else if (hunk >= 0 && /^[ +-]/.test(text)) lines.push({ text, hunk })
  }
  return lines
}

export const countDiff = (lines: DiffLine[]) => ({
  adds: lines.filter(l => l.text[0] === '+').length,
  dels: lines.filter(l => l.text[0] === '-').length,
})

// delta draws one row per diff line and one blank row between hunks.
export const firstChangedRow = (before: DiffLine[], after: DiffLine[]) => {
  let i = 0
  while (i < after.length && before[i]?.text === after[i]!.text) i++
  const line = after[Math.min(i, after.length - 1)]
  return line ? Math.min(i, after.length - 1) + line.hunk : 0
}

// The tail is what tells two paths apart.
export const tailPath = (path: string, width: number) =>
  path.length <= width ? path : `…${path.slice(path.length - Math.max(0, width - 1))}`

export const listStart = (selected: number, count: number, rows: number) =>
  Math.max(0, Math.min(selected - Math.floor(rows / 2), count - rows))

export const clamp = (n: number, low: number, high: number) => Math.max(low, Math.min(n, Math.max(low, high)))

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
    else if (p === 22) { const { bold, dim, ...rest } = s; s = rest }
    else if (p === 23) { const { it, ...rest } = s; s = rest }
    else if (p === 24) { const { u, ...rest } = s; s = rest }
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

// delta paints a changed line's background to the edge with an erase, which a Text cannot, so it becomes spaces.
export const parseAnsi = (ansi: string, width: number): Run[][] =>
  ansi.replace(/\n$/, '').split('\n').map(line => {
    const runs: Run[] = []
    let style: Style = {}
    let col = 0
    for (const part of line.split(/(\x1b\[[0-9;:]*[A-Za-z])/)) {
      const sgr = /^\x1b\[([0-9;:]*)m$/.exec(part)
      if (sgr) style = applySgr(style, (sgr[1] ?? '').split(/[;:]/).map(n => Number(n) || 0))
      else if (/^\x1b\[0?K$/.test(part)) {
        pushText(runs, style, ' '.repeat(Math.max(0, width - col)))
        col = width
      } else if (!part.startsWith('\x1b[')) {
        pushText(runs, style, part)
        col += [...part].length
      }
    }
    return runs
  })

// A Client's props past 100000 characters unmount it, so an oversized view loses its styling instead.
const VIEW_LIMIT = 80_000

export const fitRows = (rows: Run[][]): Run[][] =>
  JSON.stringify(rows).length <= VIEW_LIMIT ? rows : rows.map(row => [{ t: row.map(r => r.t).join('') }])
