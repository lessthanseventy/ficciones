import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { menardSaid, shellEdits, turnLine, emptyDiffNote, firstChangedRow, parseAnsi, parseDiff, parseLog, parseShow, patchCounts, parseStatus, printable, revealTop, splitDiff, tailPath, wrapRows } from './changes'

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

test('the list moves only as far as shows the selection', async () => {
  expect(revealTop(0, 3, 20, 5)).toBe(0)
  expect(revealTop(0, 7, 20, 5)).toBe(3)
  expect(revealTop(10, 4, 20, 5)).toBe(4)
  expect(revealTop(18, 19, 20, 5)).toBe(15)
  expect(revealTop(3, 0, 2, 5)).toBe(0)
})

test('the log reads a subject with a tab in it', async () => {
  expect(parseLog('abc1234\tfix\tthe thing\ndef5678\tsecond\n')).toEqual([
    { sha: 'abc1234', subject: 'fix\tthe thing' },
    { sha: 'def5678', subject: 'second' },
  ])
})

test('a commit splits into its message and its files, without the session link', async () => {
  const { message, files } = parseShow('Ada · 2 hours ago\n\nfix it\n\nCo-Authored-By: C <c@x>\nClaude-Session: https://claude.ai/code/session_1\n\ndiff --git a/z.ts b/z.ts\n--- a/z.ts\n+++ b/z.ts\n@@ -1 +1 @@\n-a\n+b\n')
  expect(message).toEqual(['Ada · 2 hours ago', '', 'fix it', '', 'Co-Authored-By: C <c@x>'])
  expect([...files.keys()]).toEqual(['z.ts'])
  expect(parseShow('Ada · now\n\nempty\n').files.size).toBe(0)
})

test('a long row wraps under its text, past the line numbers', async () => {
  const short = [{ t: ' 1 ⋮ 1 │one' }]
  const long = [{ t: ' 2 ⋮   │' }, { b: '#3f0001', t: 'abcdefghijklmnopqrstuvwxyz' }]
  const { rows, starts } = wrapRows([short, long, short], 20)
  expect(starts).toEqual([0, 1, 4])
  expect(rows.map(row => row.map(r => r.t).join(''))).toEqual([
    ' 1 ⋮ 1 │one',
    ' 2 ⋮   │abcdefghijkl',
    '        mnopqrstuvwx',
    '        yz          ',
    ' 1 ⋮ 1 │one',
  ])
  expect(rows[3]![2]).toEqual({ b: '#3f0001', t: ' '.repeat(10) })
})

test('a wrapped row breaks at a space, across runs', async () => {
  const { rows } = wrapRows([[{ t: 'const ' }, { c: 'red', t: 'answer' }, { t: ' = compute(the, thing)' }]], 16)
  expect(rows.map(row => row.map(r => r.t).join(''))).toEqual(['const answer = ', 'compute(the, ', 'thing)'])
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

test('L opens lazygit through Ghostty.app where setsid cannot start', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  const ran: string[] = []
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    ran.push(line)
    if (e.argv[0] === 'setsid') return { deny: 'spawn setsid ENOENT' } as never
    if (e.argv[0] === 'open') return { value: { exitCode: 0, stdout: '', stderr: '' } } as never
    const stdout = e.argv[0] === 'which' ? '/opt/homebrew/bin/lazygit\n' : line.includes(' status ') ? ' M a.ts\0' : ''
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
  on('session.cwd', async () => ({ value: '/repo' }) as never)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as {
    key: (k: { key: string }) => Promise<void>
  }
  await ui.key({ key: 'L' })
  expect(ran).toContain('open -na Ghostty.app --args --working-directory=/repo -e /opt/homebrew/bin/lazygit')
})

test('the pane is up from the start in a repository, /changes hides and shows it, /diff shows it', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  const seen: string[] = []
  on('ui.open', async ($, e) => {
    seen.push(`open ${e.id}`)
    return { value: { isPlaced: true } } as never
  })
  on('ui.close', async ($, e) => {
    seen.push(`close ${e.id}`)
    return { value: undefined } as never
  })
  on('command.register', async () => ({ value: undefined }) as never)
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }) as never)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  expect(seen).toEqual(['open changes'])
  await $.command.run({ command: 'changes', args: '' } as never)
  await $.command.run({ command: 'changes', args: '' } as never)
  await $.command.run({ command: 'diff', args: '' } as never)
  expect(seen).toEqual(['open changes', 'close changes', 'open changes', 'open changes'])
})

const DIFFS = 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\ndiff --git a/b.ts b/b.ts\n--- a/b.ts\n+++ b/b.ts\n@@ -1 +1 @@\n-p\n+q\ndiff --git a/c.ts b/c.ts\n--- a/c.ts\n+++ b/c.ts\n@@ -1 +1 @@\n-m\n+n\n'

const repo = (on: On, diff = DIFFS, status = ' M a.ts\0 M b.ts\0 M c.ts\0') => {
  const ran: string[] = []
  on('session.start', async ($, e) => e)
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)
  on('command.register', async () => ({ value: undefined }) as never)
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    ran.push(line)
    const stdout = line.includes(' status ') ? status : line.startsWith('delta') ? `\n${e.init?.stdin}` : diff
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
  return ran
}

type Mounted = {
  unmount: () => Promise<void>
  key: (k: { key: string }) => Promise<void>
  find: (q: { text: RegExp; in: string }) => Promise<unknown>
}

test('a commit opens on its message, and its files take the files list', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    const stdout = line.includes(' status ') ? ' M a.ts\0'
      : line.includes(' log ') ? 'abc1234\tfix the thing\n'
      : line.includes('rev-parse') ? '/home/ada/trees/e4\nfix/thing\n'
      : line.includes(' show ') ? 'Ada · 2 hours ago\n\nfix the thing\n\nClaude-Session: https://claude.ai/code/session_1\n\ndiff --git a/z.ts b/z.ts\n--- a/z.ts\n+++ b/z.ts\n@@ -1 +1 @@\n-before\n+after\n'
      : line.startsWith('delta') ? `\n${e.init?.stdin}`
      : 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\n'
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^commits · fix\/thing · e4/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^files · uncommitted/, in: 'changes' })).toBeDefined()
  await ui.key({ key: 'tab' })
  await ui.key({ key: 'j' })
  expect(await ui.find({ text: /^abc1234 fix the thing$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /Ada · 2 hours ago/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /Claude-Session/, in: 'changes' })).toBeUndefined()
  expect(await ui.find({ text: /^files in abc1234/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^a\.ts/, in: 'changes' })).toBeUndefined()
  await ui.key({ key: 'tab' })
  await ui.key({ key: 'j' })
  expect(await ui.find({ text: /^z\.ts$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /\+after/, in: 'changes' })).toBeDefined()
  await ui.key({ key: 'k' })
  expect(await ui.find({ text: /Ada · 2 hours ago/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /○ held/, in: 'changes' })).toBeDefined()
  await ui.key({ key: 'f' })
  expect(await ui.find({ text: /● following/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^files · uncommitted/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^a\.ts/, in: 'changes' })).toBeDefined()
  await ui.key({ key: 'f' })
  expect(await ui.find({ text: /○ held/, in: 'changes' })).toBeDefined()
})

test('the hint says who has the keyboard', async ($, on) => {
  mock.clock(on)
  repo(on, 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\n', ' M a.ts\0')
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /keys go to the prompt/, in: 'changes' })).toBeDefined()
  await ui.key({ key: 'j' })
  expect(await ui.find({ text: /CHANGES/, in: 'changes' })).toBeDefined()
})

test('a menard call is named by what it did', async () => {
  const reply = [{ type: 'text', text: '{"did":"edit cart.ex: 2 replacements","changed":[]}' }]
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__edit', input: { edits: [{ file: 'lib/cart.ex' }] }, output: reply })).toBe('edit cart.ex: 2 replacements')
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__edit', input: { edits: [{ file: 'lib/cart.ex', old: 'a', new: 'b' }] } })).toBe('edit lib/cart.ex')
  expect(menardSaid({ tool: 'Bash', input: { command: "cd x && ~/projects/menard/bin/menard edit - <<'EOF'\n…" }, output: { stdout: '{"did":"edit a.ts: 1 replacement"}' } })).toBe('edit a.ts: 1 replacement')
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__run', input: { verb: 'test' }, output: '{"ok":false,"failures":[]}' })).toBe('run test: failed')
  expect(menardSaid({ tool: 'Bash', input: { command: 'ls' }, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Read', input: { file_path: 'menard edit' } })).toBeNull()
})

test('a call becomes a line a turn can be summarised from', async () => {
  expect(turnLine({ tool: 'Edit', input: { tool: 'Edit', file_path: 'lib/a.ts' }, output: { structuredPatch: [{ lines: ['-a', '+b', '+c'] }] } }, false)).toBe('Edit lib/a.ts +2 -1')
  expect(turnLine({ tool: 'Bash', input: { tool: 'Bash', command: 'mise run check\necho done' }, output: {} }, true)).toBe('Bash mise run check (failed)')
  expect(turnLine({ tool: 'mcp__plugin_menard_menard__run', input: { verb: 'test' }, output: '{"ok":true}' }, false)).toBe('menard run test: ok')
})

test('the files a shell command changed are counted from its result', async () => {
  const output = { stdout: '', bashEditDiff: { files: [{ filePath: '/repo/lib/a.ts', hunks: [{ lines: [' x', '-a', '+b', '+c'] }] }] } }
  expect(shellEdits(output)).toEqual([{ name: 'a.ts', adds: 2, dels: 1 }])
  expect(shellEdits({ stdout: 'ok' })).toEqual([])
})

test('an edit is counted from its own result', async () => {
  expect(patchCounts({ structuredPatch: [{ lines: [' a', '-b', '+c', '+d'] }, { lines: ['-e'] }] })).toEqual({ adds: 2, dels: 2 })
  expect(patchCounts({ type: 'create', structuredPatch: [], content: 'a\nb\n' })).toEqual({ adds: 2, dels: 0 })
  expect(patchCounts(undefined)).toEqual({ adds: 0, dels: 0 })
})

test('the wheel over a list walks its selection', async ($, on) => {
  mock.clock(on)
  const names = Array.from({ length: 20 }, (_, i) => `f${i + 1}.ts`)
  repo(on, names.map(n => `diff --git a/${n} b/${n}\n--- a/${n}\n+++ b/${n}\n@@ -1 +1 @@\n-x\n+y\n`).join(''), names.map(n => ` M ${n}\0`).join(''))
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^f1\.ts/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^f15\.ts/, in: 'changes' })).toBeUndefined()
  // 30 rows: the diff's box around 15 rows, the files' top edge, then seven files from row 18
  await $.ui.scroll({ component: 'Pane', requestId: 'changes', offset: 8, by: 8, bodyRows: 30, contentRows: 30, origin: { kind: 'person' }, pointer: { column: 3, row: 22 } } as never)
  expect(await ui.find({ text: /^f2\.ts$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /held/, in: 'changes' })).toBeDefined()
})

// The engine reuses its cached drawing on a reopen, so no ui.render fires: the test mounts nothing.
test('a pane opened without a fresh render polls', async ($, on) => {
  const clock = mock.clock(on)
  const ran = repo(on)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  await clock.advance(2000)
  expect(ran.filter(line => line.includes(' status ')).length).toBeGreaterThan(0)
})

test('a view mounted again still reaches the pane', async ($, on) => {
  mock.clock(on)
  repo(on)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const first = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await first.find({ text: /following/, in: 'changes' })
  await first.key({ key: 'j' })
  expect(await first.find({ text: /^b\.ts$/, in: 'changes' })).toBeDefined()
  await first.unmount()
  const second = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await second.key({ key: 'j' })
  expect(await second.find({ text: /^c\.ts$/, in: 'changes' })).toBeDefined()
})

test('a key the pane does not bind leaves it following', async ($, on) => {
  mock.clock(on)
  repo(on)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.find({ text: /following/, in: 'changes' })
  await ui.key({ key: 'z' })
  expect(await ui.find({ text: /following/, in: 'changes' })).toBeDefined()
})

test('a file with no text diff says why', async ($, on) => {
  mock.clock(on)
  repo(on, 'diff --git a/b.bin b/b.bin\nindex 1..2 100644\nBinary files a/b.bin and b/b.bin differ\n', ' M b.bin\0')
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /binary file/, in: 'changes' })).toBeDefined()
})

test('a diff with no hunks still splits, and the note names it', async () => {
  const split = splitDiff('diff --git a/b c.bin b/b c.bin\nBinary files a/b c.bin and b/b c.bin differ\ndiff --git a/run b/run\nold mode 100644\nnew mode 100755\n')
  expect([...split.keys()]).toEqual(['b c.bin', 'run'])
  expect(emptyDiffNote(split.get('b c.bin')!)).toMatch(/binary/)
  expect(emptyDiffNote(split.get('run')!)).toMatch(/mode/)
  expect(emptyDiffNote('diff --git a/e b/e\nnew file mode 100644\nindex 0..0\n')).toMatch(/empty/)
  expect(emptyDiffNote('')).toMatch(/no diff/)
})

test('the hint names the way back to the prompt', async ($, on) => {
  mock.clock(on)
  repo(on)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.key({ key: 'j' })
  expect(await ui.find({ text: /Esc to prompt/, in: 'changes' })).toBeDefined()
})

test('a control character in a file or its name cannot break the view', async ($, on) => {
  expect(parseAnsi('\x1b[31ma\x07b\x7fc\x9bd\x1be\x1b[0m', 9)).toEqual([[{ c: 'red', t: 'a·b·c·d·e' }]])
  expect(printable('a\nb')).toBe('a·b')
  mock.clock(on)
  repo(on, 'diff --git a/a\x07.ts b/a\x07.ts\n--- a/a\x07.ts\n+++ b/a\x07.ts\n@@ -1 +1 @@\n-x\x1b\n+y\x07\n', ' M a\x07.ts\0')
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /following/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^a·\.ts$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /y·/, in: 'changes' })).toBeDefined()
})

test('the wheel moves the diff under its header, and holds it', async ($, on) => {
  mock.clock(on)
  const added = Array.from({ length: 60 }, (_, i) => `+l${i + 1}`).join('\n')
  repo(on, `diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -0,0 +1,60 @@\n${added}\n`, ' M a.ts\0')
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /\+l1\b/, in: 'changes' })).toBeDefined()
  await $.ui.scroll({ component: 'Pane', requestId: 'changes', offset: 10, by: 10, bodyRows: 30, contentRows: 30, origin: { kind: 'person' } } as never)
  expect(await ui.find({ text: /\+l1\b/, in: 'changes' })).toBeUndefined()
  expect(await ui.find({ text: /\+l20\b/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /held/, in: 'changes' })).toBeDefined()
})
