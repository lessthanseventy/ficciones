import { expect, mock, test } from 'claude-code/testing'

import { firstChangedRow, listStart, parseAnsi, parseDiff, parseStatus, splitDiff, tailPath } from './changes'

const DIFF = [
  'diff --git a/x b/x', '--- a/x', '+++ b/x',
  '@@ -1,3 +1,4 @@', ' one', '+two', ' three', ' four',
  '@@ -20,2 +21,1 @@', ' twenty', '-gone',
].join('\n')

test('status reads a rename and a spaced path', async () => {
  expect(parseStatus('R  new.ts\0old.ts\0 M a b.ts\0?? c.ts\0')).toEqual([
    { path: 'new.ts', isUntracked: false },
    { path: 'a b.ts', isUntracked: false },
    { path: 'c.ts', isUntracked: true },
  ])
})

test('a whole diff splits by file, deletions and spaced paths too', async () => {
  const split = splitDiff('diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-x\n+y\ndiff --git a/gone b/gone\n--- a/gone\n+++ /dev/null\n@@ -1 +0,0 @@\n-z\ndiff --git a/s p b/s p\n--- a/s p\t\n+++ b/s p\t\n')
  expect([...split.keys()]).toEqual(['a', 'gone', 's p'])
  expect(split.get('a')).toContain('+y')
})

test('a long path keeps its filename', async () => {
  expect(tailPath('docs/plans/2026-08-20-panels.md', 12)).toBe('…0-panels.md')
  expect(tailPath('short.md', 12)).toBe('short.md')
})

test('the first changed row counts the blank row between hunks', async () => {
  const lines = parseDiff(DIFF)
  expect(lines).toHaveLength(6)
  const later = parseDiff(DIFF.replace('-gone', '-went'))
  expect(firstChangedRow(lines, later)).toBe(6)
  expect(firstChangedRow([], lines)).toBe(0)
  expect(firstChangedRow(lines, [])).toBe(0)
})

test('ansi becomes runs, and an erase paints to the edge', async () => {
  expect(parseAnsi('\x1b[38;5;196ma\x1b[48;2;1;2;3mb\x1b[0m\n', 5)).toEqual([[{ c: '#ff0000', t: 'a' }, { c: '#ff0000', b: '#010203', t: 'b' }]])
  expect(parseAnsi('\x1b[48;2;1;2;3mab\x1b[0K\x1b[0m', 5)).toEqual([[{ b: '#010203', t: 'ab   ' }]])
})

test('the list follows the selection', async () => {
  expect(listStart(0, 20, 5)).toBe(0)
  expect(listStart(10, 20, 5)).toBe(8)
  expect(listStart(19, 20, 5)).toBe(15)
  expect(listStart(0, 2, 5)).toBe(0)
})

const PANE = {
  component: 'Pane',
  requestId: 'changes',
  props: { title: 'Changes', isFocused: true, bodyColumns: 50, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

test('a key holds the view, and nothing can stage', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  const ran: string[] = []
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    ran.push(line)
    const stdout = line.includes(' status ') ? ' M a.ts\0 M b.ts\0'
      : line.startsWith('delta') ? `\n${e.init?.stdin}`
      : 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\ndiff --git a/b.ts b/b.ts\n--- a/b.ts\n+++ b/b.ts\n@@ -1 +1 @@\n-p\n+q\n'
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as {
    key: (k: { key: string }) => Promise<void>
    find: (q: { text: RegExp; in: string }) => Promise<unknown>
  }
  expect(await ui.find({ text: /following/, in: 'changes' })).toBeDefined()
  await ui.key({ key: 'j' })
  await ui.key({ key: ' ' })
  expect(await ui.find({ text: /held/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^b\.ts$/, in: 'changes' })).toBeDefined()
  expect(ran.filter(line => /\b(add|reset|commit)\b/.test(line))).toEqual([])
})

test('/changes and /diff open the one pane', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  const opened: string[] = []
  on('ui.open', async ($, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } } as never
  })
  on('command.register', async () => ({ value: undefined }) as never)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'changes', args: '' } as never)
  await $.command.run({ command: 'diff', args: '' } as never)
  expect(opened).toEqual(['changes', 'changes'])
})
