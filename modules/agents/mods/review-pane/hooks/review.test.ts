import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { landPrompt, noteBlock } from './review'

const RANGE = { repo: '/w/api', branch: 'retry-queue', base: 'origin/main' }

test('the notes go as one message, each on its line of the diff', async () => {
  expect(noteBlock([
    { file: 'lib/queue.ex', at: 12, code: '+  retry(job)', note: 'cap the retries' },
    { file: 'README.md', at: 0, code: '', note: 'say what changed' },
  ], RANGE)).toBe([
    'I reviewed retry-queue against origin/main in /w/api and left 2 notes on its diff. Address each one, and say what you did about it:',
    '',
    '- lib/queue.ex:12 `+  retry(job)`: cap the retries',
    '- README.md: say what changed',
  ].join('\n'))
})

test('the pull request is asked for by the rules of the repository, with a question before the push', async () => {
  const said = landPrompt(RANGE, 3, 1)
  expect(said).toContain('retry-queue against origin/main in /w/api (3 commits, 1 file)')
  expect(said).toContain('Ask me before you push')
})

const PANE = {
  component: 'Pane',
  requestId: 'review',
  props: { title: 'Review', isFocused: true, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
} as const

const DIFF = 'diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-x\n+y\ndiff --git a/lib/b.ts b/lib/b.ts\n--- a/lib/b.ts\n+++ b/lib/b.ts\n@@ -4,2 +4,3 @@\n four\n+five\n six\n'

// A repository on `branch`, whose refs are the keys of `refs`: each the commit this branch parted from it at.
const repo = (on: On, branch: string, refs: Record<string, string>) => {
  const ran: string[] = []
  on('session.start', async ($, e) => e)
  on('session.cwd', async () => ({ value: '/w/api' }) as never)
  on('command.register', async () => ({ value: undefined }) as never)
  on('ui.open', async ($, e) => {
    ran.push(`open ${e.id}`)
    return { value: { isPlaced: true } } as never
  })
  on('process.run', async ($, e) => {
    const line = e.argv.join(' ')
    ran.push(line)
    const ok = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '' } }) as never
    const no = { value: { exitCode: 128, stdout: '', stderr: 'fatal' } } as never
    if (line.startsWith('delta')) return ok(`\n${e.init?.stdin}`)
    if (line.includes('--show-toplevel')) return ok('/w/api\n')
    const named = / rev-parse --abbrev-ref (\S+)$/.exec(line)?.[1]
    if (named === 'HEAD') return ok(`${branch}\n`)
    if (named === 'origin/HEAD') return 'origin/main' in refs ? ok('origin/main\n') : no
    if (named) return no
    const from = / merge-base HEAD (\S+)$/.exec(line)?.[1]
    if (from) return from in refs ? ok(`${refs[from]}\n`) : no
    if (line.includes(' status ')) return ok(' M a.ts\0?? new.ts\0')
    if (line.includes(' rev-list ')) return ok('3\n')
    if (line.includes('--no-index')) return ok('diff --git a/new.ts b/new.ts\n--- /dev/null\n+++ b/new.ts\n@@ -0,0 +1 @@\n+fresh\n')
    return line.includes(' diff ') ? ok(DIFF) : ok('')
  })
  return ran
}

type Mounted = {
  press: (k: { key: string }) => Promise<void>
  find: (q: { text: RegExp; in?: string }) => Promise<unknown>
  input: (q: { key: string; text: string; kind?: 'submit' }) => Promise<unknown>
  pointer: (e: { type: 'down'; x: number; y: number; in: string }) => Promise<unknown>
}

test('nothing opens until /land, which shows the branch against where it left the base, uncommitted work too', async ($, on) => {
  mock.clock(on)
  const ran = repo(on, 'retry-queue', { 'origin/main': 'f0f0f0f', main: 'aaaaaaa' })
  await $.session.start({ cwd: '/w/api', surface: 'terminal', isInteractive: true })
  expect(ran).toEqual([])
  await $.command.run({ command: 'land', args: '' } as never)
  expect(ran).toContain('open review')
  const ui = await $.ui.mount({ plugin: 'review-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^retry-queue$/ })).toBeDefined()
  expect(await ui.find({ text: /^origin\/main$/ })).toBeDefined()
  expect(await ui.find({ text: /^ · 3 commits · 3 files$/ })).toBeDefined()
  expect(await ui.find({ text: /^files · 3$/, in: 'review' })).toBeDefined()
  expect(await ui.find({ text: /^new\.ts/, in: 'review' })).toBeDefined()
  expect(ran.some(line => line.endsWith(' diff f0f0f0f --no-renames --no-color --no-ext-diff'))).toBe(true)
  expect(ran.filter(line => /\b(add|reset|commit|push)\b/.test(line))).toEqual([])
})

test('a note on a line is sent with the rest as one message, and only then is the pull request offered', async ($, on) => {
  mock.clock(on)
  repo(on, 'retry-queue', { 'origin/main': 'f0f0f0f' })
  const sent: string[] = []
  on('prompt.submit', async ($, e) => {
    sent.push(e.text)
    return { text: e.text } as never
  })
  await $.session.start({ cwd: '/w/api', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'land', args: '' } as never)
  const ui = await $.ui.mount({ plugin: 'review-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.find({ text: /^a\.ts$/, in: 'review' })
  // under the box's top edge, the second row of a.ts's diff is the line added
  await ui.pointer({ type: 'down', x: 3, y: 2, in: 'review' })
  await ui.press({ key: 'key-n' })
  await ui.input({ key: 'note', text: 'why y?', kind: 'submit' })
  expect(await ui.find({ text: /^why y\?$/ })).toBeDefined()
  await ui.press({ key: 'key-j' })
  await ui.press({ key: 'key-n' })
  await ui.input({ key: 'note', text: 'needs a test', kind: 'submit' })
  await expect(ui.press({ key: 'land' })).rejects.toBeDefined()
  await ui.press({ key: 'send' })
  expect(sent).toEqual(['I reviewed retry-queue against origin/main in /w/api and left 2 notes on its diff. Address each one, and say what you did about it:\n\n- a.ts:1 `+y`: why y?\n- lib/b.ts: needs a test'])
  expect(await ui.find({ text: /^why y\?$/ })).toBeUndefined()
  await ui.press({ key: 'land' })
  expect(sent[1]).toContain('have no notes left. Land it as a pull request')
})

test('a note can be dropped, and its head goes to its line', async ($, on) => {
  mock.clock(on)
  repo(on, 'retry-queue', { 'origin/main': 'f0f0f0f' })
  await $.session.start({ cwd: '/w/api', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'land', args: '' } as never)
  const ui = await $.ui.mount({ plugin: 'review-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  await ui.find({ text: /^a\.ts$/, in: 'review' })
  await ui.press({ key: 'key-n' })
  await ui.input({ key: 'note', text: 'rename this file', kind: 'submit' })
  await ui.press({ key: 'key-j' })
  expect(await ui.find({ text: /^b\.ts$/, in: 'review' })).toBeDefined()
  await ui.press({ key: 'goto-0' })
  expect(await ui.find({ text: /^a\.ts$/, in: 'review' })).toBeDefined()
  await ui.press({ key: 'drop-0' })
  expect(await ui.find({ text: /^rename this file$/ })).toBeUndefined()
})

test('on the main branch the review is of what is not pushed, and with no other branch it says so', async ($, on) => {
  mock.clock(on)
  const ran = repo(on, 'main', { 'origin/main': 'f0f0f0f', main: 'aaaaaaa' })
  await $.session.start({ cwd: '/w/api', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'land', args: '' } as never)
  const ui = await $.ui.mount({ plugin: 'review-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^origin\/main$/ })).toBeDefined()
  expect(ran.some(line => line.includes(' merge-base HEAD main'))).toBe(false)
})

test('a branch with nothing to be read against says so', async ($, on) => {
  mock.clock(on)
  repo(on, 'main', {})
  await $.session.start({ cwd: '/w/api', surface: 'terminal', isInteractive: true })
  await $.command.run({ command: 'land', args: '' } as never)
  const ui = await $.ui.mount({ plugin: 'review-pane', surface: 'terminal', ...PANE } as never) as never as Mounted
  expect(await ui.find({ text: /^nothing to review main against/ })).toBeDefined()
})
