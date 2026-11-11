import { expect, test } from 'claude-code/testing'

import { describe, duration, feedRow, graph, modelName, nodeOf } from './activity'

test('a call lands on the node it reaches', async () => {
  expect(nodeOf({ tool: 'Bash', command: 'ls' })).toBe('shell')
  expect(nodeOf({ tool: 'Bash', command: '~/projects/menard/bin/menard run test' })).toBe('menard')
  expect(nodeOf({ tool: 'mcp__plugin_menard_menard__edit' })).toBe('menard')
  expect(nodeOf({ tool: 'mcp__claude_ai_Slack__slack_send_message' })).toBe('mcp')
  expect(nodeOf({ tool: 'Edit', file_path: '/repo/lib/a.ex' })).toBe('files')
  expect(nodeOf({ tool: 'Write', file_path: '/home/a/.claude/projects/x/memory/note.md' })).toBe('memory')
  expect(nodeOf({ tool: 'WebFetch', url: 'https://docs.example.com/a' })).toBe('network')
  expect(nodeOf({ tool: 'Agent', description: 'Read the docs' })).toBe('agents')
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
  const row = feedRow({ node: 'shell', text: 'Run the whole test suite of the repository', state: 'failed', ms: 1500 }, 30)
  expect(row.map(r => r.t).join('')).toBe('✕ Shell    Run the who…  1.5 s')
  expect(row[1]!.c).toBe('error')
})

test('the wheel holds every node, and lights the spoke in use', async () => {
  const rows = graph(72, 17, { counts: { shell: 3, model: 6 }, running: new Set(['shell']), failed: new Set(), centre: ['ctx 73%', 'CLAUDE', 'fable 5.2'], isBusy: true })
  const drawn = rows.map(row => row.map(r => r.t).join(''))
  expect(rows).toHaveLength(17)
  expect(drawn.every(line => [...line].length === 72)).toBe(true)
  for (const name of ['You', 'Model 6', 'Files', '● Shell 3', 'Menard', 'Network', 'Agents', 'MCP', 'Skills', 'Memory', 'CLAUDE']) expect(drawn.join('\n')).toContain(name)
  expect(rows.flat().some(r => r.c === 'claude' && /[⠁-⣿]/.test(r.t))).toBe(true)
})
