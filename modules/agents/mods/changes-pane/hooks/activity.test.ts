import { expect, test } from 'claude-code/testing'

import { agentRow, describe, duration, feedRow, graph, heartbeat, isInTransit, isMoving, modelName, nodeOf, pulsesOf, satelliteRows, turnRow } from './activity'

test('a call lands on the node it reaches', async () => {
  expect(nodeOf({ tool: 'Bash', command: 'ls' })).toBe('shell')
  expect(nodeOf({ tool: 'Bash', command: '~/projects/menard/bin/menard run test' })).toBe('menard')
  expect(nodeOf({ tool: 'mcp__plugin_menard_menard__edit' })).toBe('menard')
  expect(nodeOf({ tool: 'mcp__claude_ai_Slack__slack_send_message' })).toBe('mcp')
  expect(nodeOf({ tool: 'Edit', file_path: '/repo/lib/a.ex' })).toBe('files')
  expect(nodeOf({ tool: 'Write', file_path: '/home/a/.claude/projects/x/memory/note.md' })).toBe('memory')
  expect(nodeOf({ tool: 'WebFetch', url: 'https://docs.example.com/a' })).toBe('network')
  expect(nodeOf({ tool: 'Agent', description: 'Read the docs' })).toBe('agents')
  expect(nodeOf({ tool: 'SubagentHandback' })).toBe('agents')
})

test('a call is said in a few words', async () => {
  expect(describe({ tool: 'Bash', command: 'mix test', description: 'Run the test suite' })).toBe('Run the test suite')
  expect(describe({ tool: 'Edit', file_path: '/repo/tests/session.test.ts' })).toBe('Edit session.test.ts')
  expect(describe({ tool: 'WebFetch', url: 'https://docs.example.com/a/b' })).toBe('WebFetch docs.example.com')
  expect(describe({ tool: 'mcp__plugin_menard_menard__edit' })).toBe('edit')
  expect(modelName('claude-fable-5-2')).toBe('fable 5.2')
  expect(duration(560)).toBe('600 ms')
  expect(duration(1500)).toBe('1.5 s')
})

test('a feed row keeps its duration when the text is cut', async () => {
  const row = feedRow({ node: 'shell', text: 'Run the whole test suite of the repository', state: 'failed', at: 0, ms: 1500 }, 30)
  expect(row.map(r => r.t).join('')).toBe('✕ Shell    Run the who…  1.5 s')
  expect(row[1]!.c).toBe('error')
})

test('a subagent reads in one line, and its calls carry its name', async () => {
  const agent = { id: 'a1', name: 'Read the hunk docs', model: 'haiku 5.5', state: 'running' as const, step: 3, doing: 'WebFetch hunk.dev', started: 1000 }
  expect(agentRow(agent, 60, 13_000)).toBe('● Read the hunk docs · haiku 5.5 · WebFetch hunk.dev  12.0 s')
  expect(agentRow(agent, 40, 13_000)).toBe('● Read the hunk docs · haiku 5.…  12.0 s')
  expect(agentRow({ ...agent, state: 'done', ms: 61_000 }, 60, 0)).toBe('· Read the hunk docs · haiku 5.5 · 3 steps  1m 1s')
  const row = feedRow({ node: 'network', text: 'WebFetch hunk.dev', state: 'done', at: 0, ms: 600, agent: 'Read the hunk docs' }, 60)
  expect(row.map(r => r.t).join('')).toBe('· Network  Read the hunk… ▸ WebFetch hunk.dev  600 ms')
})

const WHEEL = {
  counts: { shell: 3, model: 6 },
  running: new Set(['shell'] as const),
  failed: new Set<never>(),
  flashing: new Set<never>(),
  isOdd: false,
  pulses: [],
  shares: {},
  agents: [],
  centre: ['ctx 73%', 'CLAUDE', 'fable 5.2'],
  percent: 73,
  isBusy: true,
  now: 0,
}
const drawn = (rows: { t: string }[][]) => rows.map(row => row.map(r => r.t).join(''))

test('the wheel holds every node, and lights the spoke in use', async () => {
  const rows = graph(72, 17, WHEEL)
  expect(rows).toHaveLength(17)
  expect(drawn(rows).every(line => [...line].length === 72)).toBe(true)
  for (const name of ['You', 'Model 6', 'Files', '● Shell 3', 'Menard', 'Network', 'Agents', 'MCP', 'Skills', 'Memory', 'CLAUDE']) expect(drawn(rows).join('\n')).toContain(name)
  expect(rows.flat().some(r => r.c === 'claude' && r.bold && /[⠁-⣿]/.test(r.t))).toBe(true)
})

test('the inner ring fills with the context, and the outer is the time of the turn by node', async () => {
  const rows = graph(72, 17, { ...WHEEL, shares: { model: 3000, shell: 1000 } })
  const heavy = rows.flat().filter(r => /[━┃┏┓┗┛]/.test(r.t))
  const cells = (c: string) => heavy.filter(r => r.c === c).reduce((sum, r) => sum + [...r.t].filter(ch => /[━┃┏┓┗┛]/.test(ch)).length, 0)
  // the inner ring is 32 cells, 73% of them filled in the colour of a window filling up
  expect(cells('warning')).toBe(23)
  // the outer is 40 cells, three in four the model's
  expect(cells('remember')).toBe(30)
  expect(cells('claude')).toBe(10)
})

test('a call is a dot out to its node, there while it runs, and back when it has answered', async () => {
  const call = { node: 'shell' as const, text: 'ls', state: 'running' as const, at: 1000 }
  expect(pulsesOf([call], 1300)).toEqual([{ node: 'shell', p: 0.5 }])
  expect(pulsesOf([call], 9000)).toEqual([{ node: 'shell', p: 1 }])
  expect(pulsesOf([{ ...call, state: 'done', ms: 2000 }], 3300)).toEqual([{ node: 'shell', p: 0.5 }])
  expect(pulsesOf([{ ...call, state: 'done', ms: 2000 }], 4000)).toEqual([])
  expect(isMoving([{ ...call, state: 'done', ms: 2000 }], [], 4000)).toBe(false)
  expect(isMoving([{ ...call, state: 'failed', ms: 2000 }], [], 4000)).toBe(true)
  // a call that only runs is a clock to keep, not a dot to move
  expect(isMoving([call], [], 9000)).toBe(true)
  expect(isInTransit([call], 9000)).toBe(false)
  expect(isInTransit([call], 1300)).toBe(true)
  const rows = graph(72, 17, { ...WHEEL, pulses: [{ node: 'you', p: 0.5 }] })
  // the dot on the spoke, beside the mark of the node in use
  expect(drawn(rows).join('').split('●')).toHaveLength(3)
})

test('a failed call scars its spoke, and blinks while it is fresh', async () => {
  const scarred = graph(72, 17, { ...WHEEL, running: new Set(), failed: new Set(['shell'] as const) })
  expect(drawn(scarred).join('\n')).toContain('✕ Shell 3')
  const lit = graph(72, 17, { ...WHEEL, running: new Set(), flashing: new Set(['shell'] as const), isOdd: true })
  const dark = graph(72, 17, { ...WHEEL, running: new Set(), flashing: new Set(['shell'] as const), isOdd: false })
  expect(lit.flat().some(r => r.c === 'error' && r.bold && r.t.includes('Shell'))).toBe(true)
  expect(dark.flat().some(r => r.c === 'error' && r.dim && r.t.includes('Shell'))).toBe(true)
})

test('the subagents hang under the wheel, each with the node it is using', async () => {
  const agent = { id: 'a1', name: 'Count the lines', model: 'haiku 5.5', state: 'running' as const, step: 1, doing: 'ls', node: 'shell' as const, started: 0 }
  const rows = graph(72, 17 + satelliteRows(1), { ...WHEEL, agents: [agent] })
  expect(rows).toHaveLength(20)
  expect(drawn(rows)[19]).toMatch(/^ ◉ Count the… [●╌]{3} ● Shell/)
  expect(satelliteRows(0)).toBe(0)
})

test('the heartbeat is the last minutes, a cell a slice: how busy, by which node, and where a call failed', async () => {
  const row = heartbeat([
    { node: 'shell', text: 'a', state: 'failed', at: 13_000, ms: 500 },
    { node: 'model', text: 'b', state: 'done', at: 8000, ms: 4000 },
    { node: 'files', text: 'c', state: 'done', at: 5000, ms: 1000 },
  ], 5, 20_000)
  expect(row.map(r => r.t).join('')).toBe('·▃█✕·')
  expect(row.map(r => r.c)).toEqual([undefined, 'claude', 'remember', 'error', undefined])
})

test('a turn reads in one line, its time by node at the end of it', async () => {
  const row = turnRow({ n: 7, started: 0, ms: 134_000, steps: 12, calls: 31, failed: 1, state: 'done', shares: { model: 3, shell: 1 } }, 70, 0)
  expect(row.map(r => r.t).join('')).toBe(`· turn 7    2m 14s  12 steps · 31 calls · 1 failed${' '.repeat(8)}━━━━━━━━━━━━`)
  expect(row.filter(r => r.t === '━').map(r => r.c)).toEqual([...Array(9).fill('remember'), ...Array(3).fill('claude')])
  expect(turnRow({ n: 8, started: 1000, steps: 1, calls: 0, failed: 0, state: 'running', shares: {} }, 70, 5000).map(r => r.t).join('')).toMatch(/^● turn 8 {5}4\.0 s {2}1 step · 0 calls +─{12}$/)
})
