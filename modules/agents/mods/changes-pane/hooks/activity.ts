import { clamp } from './changes'
import type { Run } from './changes'

export const NODES = [
  ['you', 'You'], ['model', 'Model'], ['files', 'Files'], ['shell', 'Shell'], ['menard', 'Menard'],
  ['network', 'Network'], ['agents', 'Agents'], ['mcp', 'MCP'], ['skills', 'Skills'], ['memory', 'Memory'],
] as const
export type NodeId = (typeof NODES)[number][0]
export type State = 'running' | 'done' | 'failed'
// `agentId` and `agent` are the subagent the entry is of and its name; absent on the main loop's.
// `at` is when it began and `ms` how long it took, absent while it runs; `turn` is the main loop's turn it fell in.
export type Entry = { node: NodeId; text: string; state: State; at: number; ms?: number; agentId?: string; agent?: string; turn?: number }
// `node` is what the subagent is using now.
export type Agent = { id: string; name: string; model: string; state: State; step: number; doing: string; node?: NodeId; started: number; ms?: number }
export type Turn = { n: number; started: number; ms?: number; steps: number; calls: number; failed: number; state: State; shares: Partial<Record<NodeId, number>> }
export type Graph = {
  counts: Partial<Record<NodeId, number>>
  running: ReadonlySet<NodeId>
  // a node whose last call failed, until one of its calls succeeds
  failed: ReadonlySet<NodeId>
  // a node whose call has only just failed; `isOdd` is which half of the blink this drawing is
  flashing: ReadonlySet<NodeId>
  isOdd: boolean
  // the node of the newest entry, lit while nothing runs
  last?: NodeId
  pulses: readonly { node: NodeId; p: number }[]
  // the turn's time by node, for the outer ring
  shares: Partial<Record<NodeId, number>>
  // the subagents to hang under the wheel, the ones to show first
  agents: readonly Agent[]
  centre: string[]
  // the context's fill, for the inner ring
  percent?: number
  isBusy: boolean
  now: number
}

// Each node has a colour of the theme, so that a row of the feed and its spoke read as one thing.
const HUE: Record<NodeId, string> = {
  you: 'success', model: 'remember', files: 'claude', shell: 'claude', menard: 'planMode',
  network: 'suggestion', agents: 'planMode', mcp: 'suggestion', skills: 'warning', memory: 'remember',
}

export const level = (percent: number) => (percent >= 85 ? 'error' : percent >= 60 ? 'warning' : 'success')
type Call = { tool: string; [key: string]: unknown }

const text = (value: unknown) => (typeof value === 'string' ? value : '')
const isMemory = (path: string) => path.includes('/memory/') || path.endsWith('MEMORY.md')

export const nodeOf = (e: Call): NodeId => {
  const { tool } = e
  if (tool.startsWith('mcp__')) return tool.includes('menard') ? 'menard' : 'mcp'
  if (tool === 'Bash') return /^\S*menard\s/.test(text(e.command)) ? 'menard' : 'shell'
  if (tool === 'WebFetch' || tool === 'WebSearch') return 'network'
  if (['Agent', 'Workflow', 'SendMessage', 'SubagentHandback'].includes(tool)) return 'agents'
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


const cut = (said: string, room: number) => (said.length > room ? `${said.slice(0, Math.max(0, room - 1))}…` : said)

/** A subagent in one line: what it was sent to do, its model, what it is doing now, and how long it has run. */
export const agentRow = ({ name, model, state, step, doing, started, ms }: Agent, columns: number, now: number) => {
  const mark = state === 'running' ? '●' : state === 'failed' ? '✕' : '·'
  const tail = `  ${duration(ms ?? now - started)}`
  const body = [name, model, state === 'running' ? doing : step > 0 ? `${step} step${step === 1 ? '' : 's'}` : ''].filter(Boolean).join(' · ')
  return `${mark} ${cut(body.replace(/\s+/g, ' '), Math.max(0, columns - 2 - tail.length))}${tail}`
}

export const feedRow = ({ node, text: said, state, ms, agent }: Entry, columns: number): Run[] => {
  const mark = state === 'running' ? '●' : state === 'failed' ? '✕' : '·'
  const tail = state === 'running' ? '  running' : ms === undefined ? '' : `  ${duration(ms)}`
  const room = Math.max(0, columns - 11 - tail.length)
  const body = `${agent ? `${cut(agent, 14)} ▸ ` : ''}${said}`.replace(/\s+/g, ' ')
  const hue = state === 'failed' ? 'error' : HUE[node]
  return [
    { t: `${mark} ${label(node).padEnd(9)}`, c: hue, ...(state === 'running' ? { bold: true as const } : {}) },
    { t: cut(body, room), ...(state === 'failed' ? { c: 'error' } : state === 'running' ? { bold: true as const } : {}) },
    { t: tail, c: state === 'failed' ? 'error' : state === 'running' ? hue : 'subtle' },
  ]
}

type Shares = Partial<Record<NodeId, number>>

/** Where the time of a set of entries went, by node; one still running counts up to now. */
export const sharesOf = (entries: readonly Entry[], now: number): Shares => {
  const shares: Shares = {}
  for (const { node, at, ms } of entries) shares[node] = (shares[node] ?? 0) + (ms ?? Math.max(0, now - at))
  return shares
}

// A share of time as cells of a row or a ring, each cell the colour of the node it went to.
const shareCells = (shares: Shares, cells: number): (string | undefined)[] => {
  const total = NODES.reduce((sum, [id]) => sum + (shares[id] ?? 0), 0)
  if (total <= 0) return Array.from({ length: cells }, () => undefined)
  let spent = 0
  const ends = NODES.map(([id]) => ({ id, end: (spent += shares[id] ?? 0) / total }))
  return Array.from({ length: cells }, (_, i) => HUE[ends.find(({ end }) => (i + 0.5) / cells <= end)?.id ?? 'model'])
}

/** A turn that has ended, or the one running, in one line: how long, how much, and where the time went. */
export const turnRow = ({ n, started, ms, steps, calls, failed, state, shares }: Turn, columns: number, now: number): Run[] => {
  const bar = shareCells(shares, 12)
  const said = `${state === 'running' ? '●' : state === 'failed' ? '✕' : '·'} turn ${n}`.padEnd(10)
  const took = duration(ms ?? now - started).padStart(8)
  const counts = `  ${steps} step${steps === 1 ? '' : 's'} · ${calls} call${calls === 1 ? '' : 's'}`
  const bad = failed > 0 ? ` · ${failed} failed` : ''
  const gap = Math.max(1, columns - said.length - took.length - counts.length - bad.length - bar.length)
  return [
    { t: said, c: state === 'failed' ? 'error' : state === 'running' ? 'claude' : 'success', ...(state === 'running' ? { bold: true as const } : {}) },
    { t: took, c: 'claude' },
    { t: counts, c: 'subtle' },
    { t: bad, c: 'error' },
    { t: ' '.repeat(gap) },
    ...bar.map(c => (c ? { t: '━', c } : { t: '─', dim: true as const })),
  ]
}

const BARS = '▁▂▃▄▅▆▇█'

/** The last minutes as one row, a cell a slice of time: its height how busy, its colour the node that was busiest, a cross where a call failed. */
export const heartbeat = (entries: readonly Entry[], columns: number, now: number, sliceMs = 4000): Run[] =>
  Array.from({ length: columns }, (_, k): Run => {
    const from = now - (columns - k) * sliceMs
    const shares: Shares = {}
    let busy = 0
    for (const { node, at, ms, state } of entries) {
      const end = at + (ms ?? Math.max(0, now - at))
      if (end < from || at >= from + sliceMs) continue
      if (state === 'failed' && end < from + sliceMs) return { t: '✕', c: 'error', bold: true }
      const overlap = Math.min(end, from + sliceMs) - Math.max(at, from)
      shares[node] = (shares[node] ?? 0) + overlap
      busy += overlap
    }
    if (busy <= 0) return { t: '·', dim: true }
    const top = NODES.map(([id]) => id).sort((a, b) => (shares[b] ?? 0) - (shares[a] ?? 0))[0]!
    return { t: BARS[Math.min(BARS.length - 1, Math.floor((busy / sliceMs) * BARS.length))]!, c: HUE[top] }
  })

const TRAVEL_MS = 600
const FLASH_MS = 1500

/** Where a call is on its spoke: out to its node while it starts, there while it runs, and back once it has answered. */
export const pulsesOf = (entries: readonly Entry[], now: number): { node: NodeId; p: number }[] =>
  entries.flatMap(({ node, at, ms, agentId }) => {
    // a subagent's calls travel its own satellite, not the hub's spokes
    if (agentId !== undefined) return []
    if (ms === undefined) return [{ node, p: Math.min(1, (now - at) / TRAVEL_MS) }]
    const back = (now - at - ms) / TRAVEL_MS
    return back >= 0 && back < 1 ? [{ node, p: 1 - back }] : []
  })

/** The nodes whose call failed a moment ago. */
export const flashingOf = (entries: readonly Entry[], now: number) =>
  new Set(entries.filter(({ at, ms, state }) => state === 'failed' && ms !== undefined && now - at - ms < FLASH_MS).map(e => e.node))

/** Whether a dot is on its way or a spoke is blinking, which is what needs every frame drawn. */
export const isInTransit = (entries: readonly Entry[], now: number) =>
  entries.some(({ at, ms, state }) => (ms === undefined ? now - at < TRAVEL_MS : now - at - ms < (state === 'failed' ? FLASH_MS : TRAVEL_MS)))

/** Whether anything on the wheel is still changing, if only a clock. */
export const isMoving = (entries: readonly Entry[], agents: readonly Agent[], now: number) =>
  agents.some(a => a.state === 'running') || entries.some(({ ms }) => ms === undefined) || isInTransit(entries, now)

type Style = Pick<Run, 'c' | 'dim' | 'bold'>
type Cell = { t?: string; dots: number; style: Style; rank: number }
// A braille cell is two dots wide and four tall.
const DOT = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]] as const
const THIN = { tl: '╭', tr: '╮', bl: '╰', br: '╯', h: '─', v: '│' }
const HEAVY = { tl: '┏', tr: '┓', bl: '┗', br: '┛', h: '━', v: '┃' }
type Glyphs = typeof THIN

// The cells of a box's edge, clockwise from the middle of its top, each with the glyph its place takes.
const ring = (x0: number, y0: number, w: number, h: number) => {
  const mid = x0 + Math.floor(w / 2)
  const [x1, y1] = [x0 + w - 1, y0 + h - 1]
  const cells: { x: number; y: number; of: keyof Glyphs }[] = []
  for (let x = mid; x < x1; x++) cells.push({ x, y: y0, of: 'h' })
  cells.push({ x: x1, y: y0, of: 'tr' })
  for (let y = y0 + 1; y < y1; y++) cells.push({ x: x1, y, of: 'v' })
  cells.push({ x: x1, y: y1, of: 'br' })
  for (let x = x1 - 1; x > x0; x--) cells.push({ x, y: y1, of: 'h' })
  cells.push({ x: x0, y: y1, of: 'bl' })
  for (let y = y1 - 1; y > y0; y--) cells.push({ x: x0, y, of: 'v' })
  cells.push({ x: x0, y: y0, of: 'tl' })
  for (let x = x0 + 1; x < mid; x++) cells.push({ x, y: y0, of: 'h' })
  return cells
}

const SATELLITE_ROWS = 3
/** How many rows the subagents take under the wheel. */
export const satelliteRows = (agents: number) => (agents > 0 ? SATELLITE_ROWS : 0)

/**
 * The session as a wheel: the model at the hub, what it reaches around it, and a dot on a spoke for each
 * call out and back. Round the hub, the inner ring fills with the context and the outer is the turn's
 * time by node. The subagents hang under the Agents node, each a small hub with the node it is using.
 */
export const graph = (columns: number, rows: number, g: Graph): Run[][] => {
  const wheel = rows - satelliteRows(g.agents.length)
  const cells: Cell[][] = Array.from({ length: rows }, () => Array.from({ length: columns }, () => ({ dots: 0, style: {}, rank: -1 })))
  const write = (x: number, y: number, said: string, style: Style) => {
    ;[...said].forEach((ch, i) => {
      const cell = cells[y]?.[x + i]
      if (cell) Object.assign(cell, { t: ch, style, rank: 9 })
    })
  }
  // A line of dots between two cells, left out of any cell that holds text; the cells it took, in order.
  const line = (from: [number, number], to: [number, number], style: Style, rank: number) => {
    const [x0, y0, x1, y1] = [from[0] * 2, from[1] * 4 + 2, to[0] * 2, to[1] * 4 + 2]
    const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1)
    const path: Cell[] = []
    for (let s = 0; s <= steps; s++) {
      const dx = Math.round(x0 + ((x1 - x0) * s) / steps)
      const dy = Math.round(y0 + ((y1 - y0) * s) / steps)
      const cell = cells[dy >> 2]?.[dx >> 1]
      if (!cell || cell.t !== undefined) continue
      cell.dots |= DOT[dy & 3]![dx & 1]!
      if (rank >= cell.rank) Object.assign(cell, { style, rank })
      if (path[path.length - 1] !== cell) path.push(cell)
    }
    return path
  }

  const cx = Math.floor(columns / 2)
  const cy = Math.floor(wheel / 2)
  const widest = Math.max(...g.centre.map(said => said.length), 6)
  const left = cx - Math.floor(widest / 2) - 2
  const lines = [{ c: g.percent === undefined ? 'subtle' : level(g.percent) }, { c: 'claude', bold: true as const }, { c: 'remember' }]
  g.centre.slice(0, 3).forEach((said, i) => {
    const pad = widest - said.length
    write(left + 1, cy - 1 + i, ` ${' '.repeat(Math.floor(pad / 2))}${said}${' '.repeat(Math.ceil(pad / 2))} `, lines[i]!)
  })
  const inner = ring(left, cy - 2, widest + 4, 5)
  const filled = Math.round((Math.min(100, g.percent ?? 0) / 100) * inner.length)
  inner.forEach(({ x, y, of }, i) => {
    if (i < filled) write(x, y, HEAVY[of], { c: level(g.percent ?? 0), bold: true })
    else write(x, y, THIN[of], { c: 'claude', dim: true })
  })
  const outer = ring(left - 1, cy - 3, widest + 6, 7)
  const spent = shareCells(g.shares, outer.length)
  outer.forEach(({ x, y, of }, i) => {
    const c = spent[i]
    if (c) write(x, y, HEAVY[of], { c, ...(g.isBusy ? { bold: true as const } : {}) })
    else write(x, y, of === 'h' || of === 'v' ? '·' : ' ', { dim: true })
  })

  const rx = Math.max(4, Math.floor(columns / 2) - 12)
  const ry = Math.max(3, Math.floor(wheel / 2) - 1)
  const spokes = NODES.map(([id, name], i) => {
    const angle = -Math.PI / 2 + (i * 2 * Math.PI) / NODES.length
    const x = Math.round(cx + rx * Math.cos(angle))
    const y = Math.round(cy + ry * Math.sin(angle))
    const state = g.flashing.has(id) ? 'flash' : g.failed.has(id) ? 'failed' : g.running.has(id) || (g.running.size === 0 && g.last === id) ? 'lit' : 'idle'
    // a node the session has used keeps its colour, and one it has not stays dim
    const style: Style = state === 'flash' ? (g.isOdd ? { c: 'error', bold: true } : { c: 'error', dim: true })
      : state === 'failed' ? { c: 'error' }
      : state === 'lit' ? { c: HUE[id], bold: true }
      : g.counts[id] ? { c: HUE[id] }
      : { dim: true }
    const spoke: Style = state === 'idle' ? { ...style, dim: true } : style
    const count = g.counts[id] ? ` ${g.counts[id]}` : ''
    const mark = state === 'idle' ? '○' : state === 'lit' ? '●' : '✕'
    const side = Math.cos(angle)
    // a node left of the hub reads towards it, so its mark is the end nearest the spoke
    const said = side < -0.2 ? `${name}${count} ${mark}` : `${mark} ${name}${count}`
    const at = side < -0.2 ? x - said.length + 1 : side > 0.2 ? x : x - Math.floor(said.length / 2)
    return { id, x, y, at, said, style, spoke, rank: state === 'idle' ? 0 : state === 'lit' ? 1 : 2 }
  })
  for (const { y, at, said, style } of spokes) write(clamp(at, 0, columns - said.length), y, said, style)

  const paths = new Map<NodeId, Cell[]>()
  for (const { id, x, y, spoke, rank } of [...spokes].sort((a, b) => a.rank - b.rank)) paths.set(id, line([cx, cy], [x, y], spoke, rank))
  for (const { node, p } of g.pulses) {
    const path = paths.get(node) ?? []
    const cell = path[Math.round(clamp(p, 0, 1) * (path.length - 1))]
    if (cell) Object.assign(cell, { t: '●', style: { c: HUE[node], bold: true }, rank: 9 })
  }

  const hung = g.agents.slice(0, Math.max(1, Math.min(3, Math.floor(columns / 25))))
  const agentsNode = spokes.find(s => s.id === 'agents')!
  const width = Math.floor(columns / Math.max(1, hung.length))
  hung.forEach((agent, k) => {
    const isRunning = agent.state === 'running'
    const x = 1 + k * width
    const y = rows - 1
    const hue: Style = agent.state === 'failed' ? { c: 'error' } : isRunning ? { c: HUE.agents, bold: true } : { c: HUE.agents, dim: true }
    write(x, y, `◉ ${cut(agent.name, 10)}`, hue)
    const reach = x + 3 + Math.min(10, agent.name.length)
    if (isRunning && agent.node) {
      const dashes = [...'╌╌╌']
      // the dot takes a step along the dashes each second
      dashes[Math.floor((g.now - agent.started) / 1000) % dashes.length] = '●'
      write(reach, y, dashes.join(''), { c: HUE[agent.node], bold: true })
      write(reach + 4, y, `● ${label(agent.node)}`, { c: HUE[agent.node] })
    }
    line([agentsNode.x, agentsNode.y + 1], [x, y - 1], isRunning ? { c: HUE.agents } : { c: HUE.agents, dim: true }, isRunning ? 1 : 0)
  })

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
