import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { emptyDiffNote, firstChangedRow, parseAnsi, parseDiff, parseLog, parseShow, parseStatus, printable, revealTop, splitDiff, tailPath, wrapRows } from './changes'

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
  expect(lines.map(l => `${l.text[0]}${l.at}`)).toEqual([' 1', '+2', ' 3', ' 4', ' 21', '-21'])
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
    press: (k: { key: string }) => Promise<void>
    find: (q: { text: RegExp; in: string }) => Promise<unknown>
  }
  expect(await ui.find({ text: /following/, in: 'changes' })).toBeDefined()
  await ui.press({ key: 'key-j' })
  expect(await ui.find({ text: /held/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^b\.ts$/, in: 'changes' })).toBeDefined()
  expect(ran.filter(line => /\b(add|reset|commit)\b/.test(line))).toEqual([])
})

test('l opens lazygit through Ghostty.app where setsid cannot start', async ($, on) => {
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
    press: (k: { key: string }) => Promise<void>
  }
  await ui.press({ key: 'key-l' })
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

test('a session started outside a repository opens the pane once it moves into one', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  const seen: string[] = []
  on('ui.open', async ($, e) => {
    seen.push(`open ${e.id}`)
    return { value: { isPlaced: true } } as never
  })
  on('command.register', async () => ({ value: undefined }) as never)
  let cwd = '/home'
  on('session.cwd', async () => ({ value: cwd }) as never)
  on('process.run', async () => ({ value: { exitCode: cwd === '/repo' ? 0 : 128, stdout: '', stderr: '' } }) as never)
  on('tool.call', () => ({ result: {} }) as never)
  await $.session.start({ cwd, surface: 'terminal', isInteractive: true })
  await $.tool.call({ tool: 'Bash', command: 'ls' } as never)
  expect(seen).toEqual([])
  cwd = '/repo'
  await $.tool.call({ tool: 'Bash', command: 'cd /repo' } as never)
  expect(seen).toEqual(['open changes'])
  await $.tool.call({ tool: 'Bash', command: 'ls' } as never)
  expect(seen).toEqual(['open changes'])
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
  press: (k: { key: string }) => Promise<void>
  find: (q: { text: RegExp; in?: string }) => Promise<unknown>
}

test('a commit opens on its message, and its files take the files list', async ($, on) => {
  mock.clock(on)
  on('session.start', async ($, e) => e)
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    const stdout = line.includes(' status ') ? ' M a.ts\0'
      : line.includes(' log ') ? 'abc1234\tfix the thing\n'
      : line.includes('rev-parse') ? '/home/ada/trees/e4\nfix/thing\n/home/ada/app/.git\n'
      : line.includes(' show ') ? 'Ada · 2 hours ago\n\nfix the thing\n\nClaude-Session: https://claude.ai/code/session_1\n\ndiff --git a/z.ts b/z.ts\n--- a/z.ts\n+++ b/z.ts\n@@ -1 +1 @@\n-before\n+after\n'
      : line.startsWith('delta') ? `\n${e.init?.stdin}`
      : 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\n'
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^commits · fix\/thing · app ⑂ worktree e4/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^files · uncommitted/, in: 'changes' })).toBeDefined()
  await ui.press({ key: 'key-t' })
  await ui.press({ key: 'key-j' })
  expect(await ui.find({ text: /^abc1234 fix the thing$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /Ada · 2 hours ago/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /Claude-Session/, in: 'changes' })).toBeUndefined()
  expect(await ui.find({ text: /^files in abc1234/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^a\.ts/, in: 'changes' })).toBeUndefined()
  await ui.press({ key: 'key-t' })
  await ui.press({ key: 'key-j' })
  expect(await ui.find({ text: /^z\.ts$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /\+after/, in: 'changes' })).toBeDefined()
  await ui.press({ key: 'key-k' })
  expect(await ui.find({ text: /Ada · 2 hours ago/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /○ held/, in: 'changes' })).toBeDefined()
  await ui.press({ key: 'key-f' })
  expect(await ui.find({ text: /● following/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^files · uncommitted/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^a\.ts/, in: 'changes' })).toBeDefined()
  await ui.press({ key: 'key-f' })
  expect(await ui.find({ text: /○ held/, in: 'changes' })).toBeDefined()
})

test('the key row says who has the keyboard', async ($, on) => {
  mock.clock(on)
  repo(on, 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\n', ' M a.ts\0')
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /CHANGES/ })).toBeDefined()
  await ui.unmount()
  const away = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE, props: { ...PANE.props, isFocused: false } } as never) as never as Mounted
  expect(await away.find({ text: /○ click/ })).toBeDefined()
  expect(await away.find({ text: /CHANGES/ })).toBeUndefined()
})

test('the wheel over a list walks its selection', async ($, on) => {
  mock.clock(on)
  const names = Array.from({ length: 20 }, (_, i) => `f${i + 1}.ts`)
  repo(on, names.map(n => `diff --git a/${n} b/${n}\n--- a/${n}\n+++ b/${n}\n@@ -1 +1 @@\n-x\n+y\n`).join(''), names.map(n => ` M ${n}\0`).join(''))
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^f1\.ts/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^f15\.ts/, in: 'changes' })).toBeUndefined()
  // 30 rows: the tabs, the diff's box around 14 rows, the files' top edge, then seven files from row 18
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
  await first.press({ key: 'key-j' })
  expect(await first.find({ text: /^b\.ts$/, in: 'changes' })).toBeDefined()
  await first.unmount()
  const second = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await second.press({ key: 'key-j' })
  expect(await second.find({ text: /^c\.ts$/, in: 'changes' })).toBeDefined()
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

test('the activity tab draws the session as a wheel over the turns that have ended', async ($, on) => {
  mock.clock(on)
  repo(on)
  on('tool.call', ($, e) => ({ result: {}, ...(e.tool === 'Bash' ? { isError: true } : {}) }) as never)
  on('turn.start', async () => ({ turnId: 't1' }) as never)
  on('turn.complete', async () => ({ text: '' }) as never)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.press({ key: 'tab-activity' })
  expect(await ui.find({ text: /CLAUDE/ })).toBeDefined()
  expect(await ui.find({ text: /nothing yet this session/ })).toBeDefined()
  await $.turn.start({ turnId: 't1' } as never)
  await $.tool.call({ tool: 'Edit', file_path: '/repo/a.ts', old_string: 'x', new_string: 'y' } as never)
  expect(await ui.find({ text: /^● turn 1/ })).toBeDefined()
  await $.tool.call({ tool: 'Bash', command: 'mix test', description: 'Run the test suite' } as never)
  await $.turn.complete({ turnId: 't1', reason: 'answer' } as never)
  expect(await ui.find({ text: /^· turn 1/ })).toBeDefined()
  expect(await ui.find({ text: /^ {2}0 steps · 2 calls$/ })).toBeDefined()
  expect(await ui.find({ text: /^ · 1 failed$/ })).toBeDefined()
  // the calls themselves are the transcript's to list
  expect(await ui.find({ text: /Run the test suite/ })).toBeUndefined()
  expect(await ui.find({ text: /✕ Shell 1/ })).toBeDefined()
  expect(await ui.find({ text: /○ Files 1/ })).toBeDefined()
  await ui.press({ key: 'tab-changes' })
  expect(await ui.find({ text: /following/, in: 'changes' })).toBeDefined()
})

test('a subagent has a row of its own, and a click narrows the feed to it', async ($, on) => {
  mock.clock(on)
  repo(on)
  on('tool.call', () => ({ result: {} }) as never)
  on('agent.spawn', async () => ({ model: 'claude-haiku-5-5', agentId: 'a1' }) as never)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.press({ key: 'tab-activity' })
  await $.tool.call({ tool: 'Bash', command: 'ls', description: 'List the files' } as never)
  await $.agent.spawn({ tool_use_id: 't1', prompt: 'read them', description: 'Read the hunk docs', subagentType: 'web-fetch', parentModel: 'claude-fable-5-2', background: false, fork: false } as never)
  await $.tool.call({ tool: 'WebFetch', url: 'https://hunk.dev/docs', agentId: 'a1' } as never)
  // the pane is 50 columns wide, and a row is cut to it
  expect(await ui.find({ text: /^● Read the hunk docs · haiku 5\.5 · WebFetch/ })).toBeDefined()
  expect(await ui.find({ text: /^Read the hunk… ▸ WebFetch/ })).toBeUndefined()
  await $.tool.call({ tool: 'SubagentHandback', agentId: 'a1' } as never)
  // one subagent, whatever it has done, and its node lit while it runs
  expect(await ui.find({ text: /Agents 1 ●/ })).toBeDefined()
  expect(await ui.find({ text: /^◉ Read the …$/ })).toBeDefined()
  await ui.press({ key: 'agent-a1' })
  expect(await ui.find({ text: /^Read the hunk… ▸ WebFetch/ })).toBeDefined()
  expect(await ui.find({ text: /^▶ ● Read the hunk docs/ })).toBeDefined()
  await ui.press({ key: 'agent-a1' })
  expect(await ui.find({ text: /^Read the hunk… ▸ WebFetch/ })).toBeUndefined()
})

// Two repositories under one folder: git answers by the directory it is run in.
const repos = (on: On, at: { cwd: string; run?: () => void }, trees: Record<string, string[]>) => {
  on('session.start', async ($, e) => e)
  on('ui.open', async () => ({ value: { isPlaced: true } }) as never)
  on('command.register', async () => ({ value: undefined }) as never)
  on('session.cwd', async () => ({ value: at.cwd }) as never)
  on('tool.call', () => {
    at.run?.()
    return { result: {} } as never
  })
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    if (line.startsWith('delta')) return { value: { exitCode: 0, stdout: `\n${e.init?.stdin}`, stderr: '' } } as never
    const dir = e.init?.cwd ?? at.cwd
    const root = Object.keys(trees).find(r => dir === r || dir.startsWith(`${r}/`))
    if (!root) return { value: { exitCode: 128, stdout: '', stderr: '' } } as never
    const names = trees[root]!
    const stdout = line.includes('--show-toplevel') ? `${root}\n${line.includes('--abbrev-ref') ? 'main\n' : ''}${root}/.git\n`
      : line.includes(' status ') ? names.map(n => ` M ${n}\0`).join('')
      : line.includes(' diff ') ? names.map(n => `diff --git a/${n} b/${n}\n--- a/${n}\n+++ b/${n}\n@@ -1 +1 @@\n-x\n+y\n`).join('')
      : ''
    return { value: { exitCode: 0, stdout, stderr: '' } } as never
  })
}

test('a note on a line of the diff rides on the next prompt, once', async ($, on) => {
  mock.clock(on)
  repos(on, { cwd: '/w/api' }, { '/w/api': ['a.ts'] })
  const sent: string[] = []
  on('prompt.submit', async ($, e) => {
    sent.push(e.text)
    return { text: e.text } as never
  })
  await $.session.start({ cwd: '/w/api', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted & {
    input: (q: { key: string; text: string; kind?: 'submit' }) => Promise<unknown>
    pointer: (e: { type: 'down'; x: number; y: number; in: string }) => Promise<unknown>
  }
  await ui.find({ text: /following/, in: 'changes' })
  // under the box's top edge, the second row of a.ts's diff is the line added
  await ui.pointer({ type: 'down', x: 3, y: 2, in: 'changes' })
  await ui.press({ key: 'key-n' })
  await ui.input({ key: 'note', text: 'why y?', kind: 'submit' })
  await ui.press({ key: 'tab-review' })
  expect(await ui.find({ text: /^1 note, sent with your next message$/ })).toBeDefined()
  expect(await ui.find({ text: /api · a\.ts:1/ })).toBeDefined()
  await $.prompt.submit({ text: 'look at my note' } as never)
  await $.prompt.submit({ text: 'and again' } as never)
  expect(sent).toEqual(['look at my note\n\nReview notes I left on the diff in the changes pane:\n\nIn /w/api:\n- a.ts:1 `+y`: why y?', 'and again'])
})

test('a cd into another repository leaves the pane on the one being worked in, and an edit there moves it', async ($, on) => {
  mock.clock(on)
  const at = { cwd: '/w/api' }
  repos(on, at, { '/w/api': ['a.ts'], '/w/web': ['w1.ts', 'w2.ts'] })
  await $.session.start({ cwd: at.cwd, surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeDefined()
  at.cwd = '/w/web'
  await $.tool.call({ tool: 'Bash', command: 'cd /w/web' } as never)
  at.cwd = '/w'
  await $.tool.call({ tool: 'Bash', command: 'cd /w' } as never)
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /not a git repository/, in: 'changes' })).toBeUndefined()
  await $.tool.call({ tool: 'Edit', file_path: '/w/web/w2.ts', old_string: 'x', new_string: 'y' } as never)
  expect(await ui.find({ text: /^commits · main · web/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeUndefined()
  // the edited file, not the last of a tree that is all new to the pane
  expect(await ui.find({ text: /w2\.ts {2}\+1 -1/, in: 'changes' })).toBeDefined()
})

test('the repositories the pane has been on sit in a row, and a click holds the pane on one', async ($, on) => {
  mock.clock(on)
  const at = { cwd: '/w/api' }
  repos(on, at, { '/w/api': ['a.ts'], '/w/web': ['w1.ts', 'w2.ts'] })
  await $.session.start({ cwd: at.cwd, surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^ api 1 $/ })).toBeUndefined()
  await $.tool.call({ tool: 'Edit', file_path: '/w/web/w2.ts', old_string: 'x', new_string: 'y' } as never)
  expect(await ui.find({ text: /^ web 2 $/ })).toBeDefined()
  await ui.press({ key: 'repo-/w/api' })
  expect(await ui.find({ text: /^ api 1 $/ })).toBeDefined()
  expect(await ui.find({ text: /^web 2$/ })).toBeDefined()
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeDefined()
  expect(await ui.find({ text: /held/, in: 'changes' })).toBeDefined()
  await $.tool.call({ tool: 'Edit', file_path: '/w/web/w1.ts', old_string: 'x', new_string: 'y' } as never)
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeDefined()
})

test('a shell command that changes another repository moves the pane to it', async ($, on) => {
  mock.clock(on)
  const at: { cwd: string; run?: () => void } = { cwd: '/w/api' }
  const trees = { '/w/api': ['a.ts'], '/w/web': ['w1.ts'] }
  repos(on, at, trees)
  await $.session.start({ cwd: at.cwd, surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  at.cwd = '/w/web'
  // the tree as it was before the session came is nothing the session did
  trees['/w/web'] = ['w1.ts', 'w0.ts']
  await $.tool.call({ tool: 'Bash', command: 'ls' } as never)
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeDefined()
  at.run = () => { trees['/w/web'] = ['w1.ts', 'w0.ts', 'made.ts'] }
  await $.tool.call({ tool: 'Bash', command: 'touch made.ts' } as never)
  expect(await ui.find({ text: /^made\.ts/, in: 'changes' })).toBeDefined()
})

test('a held pane stays on its repository through an edit in another', async ($, on) => {
  mock.clock(on)
  const at = { cwd: '/w/api' }
  repos(on, at, { '/w/api': ['a.ts'], '/w/web': ['w1.ts'] })
  await $.session.start({ cwd: at.cwd, surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'changes-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.press({ key: 'key-f' })
  await $.tool.call({ tool: 'Edit', file_path: '/w/web/w1.ts', old_string: 'x', new_string: 'y' } as never)
  expect(await ui.find({ text: /^a\.ts$/, in: 'changes' })).toBeDefined()
  await ui.press({ key: 'key-f' })
  await $.tool.call({ tool: 'Edit', file_path: '/w/web/w1.ts', old_string: 'x', new_string: 'y' } as never)
  expect(await ui.find({ text: /^w1\.ts$/, in: 'changes' })).toBeDefined()
})
