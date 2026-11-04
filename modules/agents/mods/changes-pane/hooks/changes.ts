export type File = { path: string; x: string; y: string }
export type DiffLine = { text: string; old: number; new: number }

export const parseStatus = (z: string): { branch: string; files: File[] } => {
  const entries = z.split('\0')
  const files: File[] = []
  let branch = ''
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i]!
    if (entry.startsWith('## ')) {
      branch = (entry.slice(3).split('...')[0] ?? '').replace(/^No commits yet on /, '').split(' ')[0] ?? ''
    } else if (entry.length > 3) {
      const [x, y] = [entry[0]!, entry[1]!]
      files.push({ path: entry.slice(3), x, y })
      // -z puts a rename's origin in an entry of its own.
      if (x === 'R' || x === 'C' || y === 'R' || y === 'C') i++
    }
  }
  return { branch, files }
}

export const isFullyStaged = ({ x, y }: File) => x !== ' ' && x !== '?' && y === ' '

// The tail is what tells two paths apart.
export const tailPath = (path: string, width: number) =>
  path.length <= width ? path : `…${path.slice(path.length - Math.max(0, width - 1))}`

export const parseDiff = (diff: string): DiffLine[] => {
  const lines: DiffLine[] = []
  let [old, now, inHunk] = [0, 0, false]
  for (const text of diff.split('\n')) {
    const hunk = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(text)
    if (hunk) {
      old = Number(hunk[1])
      now = Number(hunk[2])
      inHunk = true
    } else if (inHunk && /^[ +-]/.test(text)) {
      lines.push({ text, old, new: now })
      if (text[0] !== '+') old++
      if (text[0] !== '-') now++
    }
  }
  return lines
}

const follows = (line: DiffLine, last: DiffLine) =>
  line.old === last.old + (last.text[0] === '+' ? 0 : 1) && line.new === last.new + (last.text[0] === '-' ? 0 : 1)

// The offset that puts the last line on the last row. Code draws a row of its own between hunks.
export const lastOffset = (lines: DiffLine[], rows: number) => {
  let used = 0
  let offset = lines.length
  while (offset > 0) {
    const gap = offset < lines.length && !follows(lines[offset]!, lines[offset - 1]!) ? 1 : 0
    if (used + gap + 1 > rows) break
    used += gap + 1
    offset--
  }
  return Math.min(offset, Math.max(0, lines.length - 1))
}

// Code parses whole hunks only, so a scrolled view is re-headed: one hunk per unbroken run of lines.
export const windowDiff = (lines: DiffLine[], offset: number, rows: number) => {
  const out: string[] = []
  let run: DiffLine[] = []
  let left = rows
  const flush = () => {
    if (run.length === 0) return
    const olds = run.filter(l => l.text[0] !== '+').length
    const news = run.filter(l => l.text[0] !== '-').length
    out.push(`@@ -${run[0]!.old},${olds} +${run[0]!.new},${news} @@`, ...run.map(l => l.text))
    run = []
  }
  for (const line of lines.slice(offset, offset + rows)) {
    const last = run[run.length - 1]
    const isBreak = last !== undefined && !follows(line, last)
    left -= isBreak ? 2 : 1
    if (left < 0) break
    if (isBreak) flush()
    run.push(line)
  }
  flush()
  return out.join('\n')
}

export const countDiff = (lines: DiffLine[]) => ({
  adds: lines.filter(l => l.text[0] === '+').length,
  dels: lines.filter(l => l.text[0] === '-').length,
})

export const listStart = (selected: number, count: number, rows: number) =>
  Math.max(0, Math.min(selected - Math.floor(rows / 2), count - rows))

export const clamp = (n: number, low: number, high: number) => Math.max(low, Math.min(n, Math.max(low, high)))
