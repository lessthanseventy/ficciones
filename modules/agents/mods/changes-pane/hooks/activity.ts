import { clamp } from './changes'
import type { Run } from './changes'

export const NODES = [
  ['you', 'You'], ['model', 'Model'], ['files', 'Files'], ['shell', 'Shell'], ['menard', 'Menard'],
  ['network', 'Network'], ['agents', 'Agents'], ['mcp', 'MCP'], ['skills', 'Skills'], ['memory', 'Memory'],
] as const
export type NodeId = (typeof NODES)[number][0]
export type State = 'running' | 'done' | 'failed'
export type Entry = { node: NodeId; text: string; state: State; ms?: number }
export type Graph = {
  counts: Partial<Record<NodeId, number>>
  running: ReadonlySet<NodeId>
  failed: ReadonlySet<NodeId>
  // the node of the newest entry, lit while nothing runs
  last?: NodeId
  centre: string[]
  isBusy: boolean
}
type Call = { tool: string; [key: string]: unknown }

const text = (value: unknown) => (typeof value === 'string' ? value : '')
const isMemory = (path: string) => path.includes('/memory/') || path.endsWith('MEMORY.md')

export const nodeOf = (e: Call): NodeId => {
  const { tool } = e
  if (tool.startsWith('mcp__')) return tool.includes('menard') ? 'menard' : 'mcp'
  if (tool === 'Bash') return /^\S*menard\s/.test(text(e.command)) ? 'menard' : 'shell'
  if (tool === 'WebFetch' || tool === 'WebSearch') return 'network'
  if (tool === 'Agent' || tool === 'Workflow' || tool === 'SendMessage') return 'agents'
  if (tool === 'Skill') return 'skills'
  if (['Read', 'Edit', 'Write', 'NotebookEdit', 'Grep', 'Glob'].includes(tool)) return isMemory(text(e.file_path)) ? 'memory' : 'files'
  return 'model'
}

export const describe = (e: Call): string => {
  const { tool } = e
  if (tool.startsWith('mcp__')) return tool.split('__').slice(2).join(' ') || tool
  const said = text(e.description) || text(e.command) || text(e.pattern) || text(e.query) || text(e.skill) || text(e.url).replace(/^https?:\/\/([^/]+).*/, '$1')
  const path = text(e.file_path) || text(e.notebook_path)
  if (path) return `${tool} ${path.split('/').pop()}`
  return said ? (tool === 'Bash' ? said : `${tool} ${said}`) : tool
}

export const modelName = (id: string) => id.replace(/^claude-/, '').replace(/-(\d+)-(\d+).*$/, ' $1.$2').replace(/-\d{8}$/, '')

export const duration = (ms: number) => (ms < 1000 ? `${Math.round(ms / 100) * 100} ms` : ms < 60_000 ? `${(ms / 1000).toFixed(1)} s` : `${Math.floor(ms / 60_000)}m ${Math.round((ms % 60_000) / 1000)}s`)

const label = (node: NodeId) => NODES.find(([id]) => id === node)![1]
const tone = (state: State): Pick<Run, 'c' | 'dim' | 'bold'> => (state === 'running' ? { c: 'claude', bold: true } : state === 'failed' ? { c: 'error' } : { dim: true })

export const feedRow = ({ node, text: said, state, ms }: Entry, columns: number): Run[] => {
  const mark = state === 'running' ? '●' : state === 'failed' ? '✕' : '·'
  const tail = state === 'running' ? '  running' : ms === undefined ? '' : `  ${duration(ms)}`
  const room = Math.max(0, columns - 11 - tail.length)
  const body = said.replace(/\s+/g, ' ')
  return [
    { t: `${mark} ${label(node).padEnd(9)}`, ...tone(state) },
    { t: body.length > room ? `${body.slice(0, Math.max(0, room - 1))}…` : body, ...(state === 'failed' ? { c: 'error' } : state === 'running' ? { c: 'claude' } : {}) },
    { t: tail, ...tone(state) },
  ]
}

type Cell = { t?: string; dots: number; style: Pick<Run, 'c' | 'dim' | 'bold'>; rank: number }
// A braille cell is two dots wide and four tall.
const DOT = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]] as const

/** The session as a wheel: the model at the hub, what it reaches around it, a spoke lit while it is in use. */
export const graph = (columns: number, rows: number, g: Graph): Run[][] => {
  const cells: Cell[][] = Array.from({ length: rows }, () => Array.from({ length: columns }, () => ({ dots: 0, style: {}, rank: -1 })))
  const write = (x: number, y: number, said: string, style: Cell['style']) => {
    ;[...said].forEach((ch, i) => {
      const cell = cells[y]?.[x + i]
      if (cell) Object.assign(cell, { t: ch, style, rank: 9 })
    })
  }
  const cx = Math.floor(columns / 2)
  const cy = Math.floor(rows / 2)
  const widest = Math.max(...g.centre.map(line => line.length), 6)
  const hub = g.isBusy ? { c: 'claude', bold: true as const } : { dim: true as const }
  write(cx - Math.floor(widest / 2) - 2, cy - 2, `╭${'─'.repeat(widest + 2)}╮`, hub)
  g.centre.slice(0, 3).forEach((line, i) => {
    const pad = widest - line.length
    write(cx - Math.floor(widest / 2) - 2, cy - 1 + i, '│', hub)
    write(cx - Math.floor(widest / 2) - 1, cy - 1 + i, ` ${' '.repeat(Math.floor(pad / 2))}${line}${' '.repeat(Math.ceil(pad / 2))} `, i === 1 ? { c: 'claude', bold: true } : {})
    write(cx + Math.ceil(widest / 2) + 1, cy - 1 + i, '│', hub)
  })
  write(cx - Math.floor(widest / 2) - 2, cy + 2, `╰${'─'.repeat(widest + 2)}╯`, hub)

  const rx = Math.max(4, Math.floor(columns / 2) - 12)
  const ry = Math.max(3, Math.floor(rows / 2) - 1)
  const spokes = NODES.map(([id, name], i) => {
    const angle = -Math.PI / 2 + (i * 2 * Math.PI) / NODES.length
    const x = Math.round(cx + rx * Math.cos(angle))
    const y = Math.round(cy + ry * Math.sin(angle))
    const state = g.failed.has(id) ? 'failed' : g.running.has(id) || (g.running.size === 0 && g.last === id) ? 'lit' : 'idle'
    const style = state === 'failed' ? { c: 'error', bold: true as const } : state === 'lit' ? { c: g.running.has(id) ? 'claude' : 'success', bold: true as const } : { dim: true as const }
    const count = g.counts[id] ? ` ${g.counts[id]}` : ''
    const mark = state === 'idle' ? '○' : state === 'failed' ? '✕' : '●'
    const side = Math.cos(angle)
    // a node left of the hub reads towards it, so its mark is the end nearest the spoke
    const said = side < -0.2 ? `${name}${count} ${mark}` : `${mark} ${name}${count}`
    const at = side < -0.2 ? x - said.length + 1 : side > 0.2 ? x : x - Math.floor(said.length / 2)
    return { x, y, at, said, style, rank: state === 'idle' ? 0 : state === 'lit' ? 1 : 2 }
  })
  for (const { y, at, said, style } of spokes) write(clamp(at, 0, columns - said.length), y, said, style)

  for (const { x, y, style, rank } of [...spokes].sort((a, b) => a.rank - b.rank)) {
    const [x0, y0, x1, y1] = [cx * 2, cy * 4 + 2, x * 2, y * 4 + 2]
    const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1)
    for (let s = 0; s <= steps; s++) {
      const dx = Math.round(x0 + ((x1 - x0) * s) / steps)
      const dy = Math.round(y0 + ((y1 - y0) * s) / steps)
      const cell = cells[dy >> 2]?.[dx >> 1]
      if (!cell || cell.t !== undefined) continue
      cell.dots |= DOT[dy & 3]![dx & 1]!
      if (rank >= cell.rank) Object.assign(cell, { style, rank })
    }
  }

  return cells.map(row => {
    const runs: Run[] = []
    for (const cell of row) {
      const t = cell.t ?? (cell.dots ? String.fromCharCode(0x2800 + cell.dots) : ' ')
      const last = runs[runs.length - 1]
      if (last && last.c === cell.style.c && last.dim === cell.style.dim && last.bold === cell.style.bold) last.t += t
      else runs.push({ t, ...cell.style })
    }
    return runs
  })
}
