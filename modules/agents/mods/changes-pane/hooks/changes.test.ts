import { expect, mock, test } from 'claude-code/testing'

import { lastOffset, listStart, parseDiff, parseStatus, tailPath, windowDiff } from './changes'

const DIFF = [
  'diff --git a/x b/x', '--- a/x', '+++ b/x',
  '@@ -1,3 +1,4 @@', ' one', '+two', ' three', ' four',
  '@@ -20,2 +21,1 @@', ' twenty', '-gone',
].join('\n')

test('status reads the branch, a rename and a spaced path', async () => {
  const { branch, files } = parseStatus('## main...origin/main [ahead 1]\0R  new.ts\0old.ts\0 M a b.ts\0?? c.ts\0')
  expect(branch).toBe('main')
  expect(files).toEqual([
    { path: 'new.ts', x: 'R', y: ' ' },
    { path: 'a b.ts', x: ' ', y: 'M' },
    { path: 'c.ts', x: '?', y: '?' },
  ])
})

test('a long path keeps its filename', async () => {
  expect(tailPath('docs/plans/2026-08-20-panels.md', 12)).toBe('…0-panels.md')
  expect(tailPath('short.md', 12)).toBe('short.md')
})

test('a window re-heads its hunks so it still parses', async () => {
  const lines = parseDiff(DIFF)
  expect(lines).toHaveLength(6)
  expect(windowDiff(lines, 0, 2)).toBe('@@ -1,1 +1,2 @@\n one\n+two')
  expect(windowDiff(lines, 2, 4)).toBe('@@ -2,2 +3,2 @@\n three\n four\n@@ -20,1 +21,1 @@\n twenty')
})

test('a hunk break costs a row, and the last offset still reaches the end', async () => {
  const lines = parseDiff(DIFF)
  expect(windowDiff(lines, 2, 3)).toBe('@@ -2,2 +3,2 @@\n three\n four')
  expect(lastOffset(lines, 3)).toBe(4)
  expect(lastOffset(lines, 4)).toBe(3)
  expect(lastOffset(lines, 100)).toBe(0)
  expect(lastOffset([], 10)).toBe(0)
})

test('the list follows the selection', async () => {
  expect(listStart(0, 20, 5)).toBe(0)
  expect(listStart(10, 20, 5)).toBe(8)
  expect(listStart(19, 20, 5)).toBe(15)
  expect(listStart(0, 2, 5)).toBe(0)
})

const PANE = {
  component: 'Pane',
  requestId: 'diff',
  props: { title: 'diff', isFocused: true, bodyColumns: 50, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

test('j moves to the next file and space stages it', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  const ran: string[] = []
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    ran.push(line)
    const stdout = line.includes(' status ') ? '## main\0 M a.ts\0 M b.ts\0' : DIFF
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as {
    key: (k: { key: string }) => Promise<void>
    find: (q: { text: RegExp; in: string }) => Promise<unknown>
  }
  await ui.key({ key: 'j' })
  await ui.key({ key: ' ' })
  expect(ran).toContain('git add -- b.ts')
  expect(await ui.find({ text: /b\.ts  \+1 -1/, in: 'changes' })).toBeDefined()
})
