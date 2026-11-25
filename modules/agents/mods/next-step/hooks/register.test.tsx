import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine, EngineCall } from 'claude-code/testing'

const BAND = {
  plugin: 'next-step',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 20,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

const ENGINE = { kind: 'suggestion' } as const

// The kit raises the box's own events, which a plugin cannot call and so are not typed on its `$`.
const box = ($: Engine) =>
  $.prompt as unknown as {
    edit: EngineCall<'prompt.edit'>
    change: EngineCall<'prompt.change'>
    submit: EngineCall<'prompt.submit'>
  }

const SURFACES = ['terminal', 'desktop'] as const

test('the ghost suggestion is a button, and a click sends it as the human', async ($, on) => {
  const sent: unknown[] = []
  on('prompt.suggest', () => ({ isShown: true }))
  on('prompt.submit', (_, e) => {
    sent.push({ text: e.text, origin: e.origin })
    return { text: e.text }
  })

  for (const surface of SURFACES) {
    sent.length = 0
    await $.prompt.suggest({ text: 'yes, drive 837', origin: ENGINE })
    const ui = await $.ui.mount({ ...BAND, surface })
    await ui.press({ key: 'next-step' })
    expect(sent).toEqual([{ text: 'yes, drive 837', origin: { kind: 'plugin', name: 'next-step', asUser: true } }])
    expect(await ui.find({ key: 'next-step' })).toBeUndefined()
    await ui.unmount()
  }
})

test('typing in the box takes the button away', async ($, on) => {
  on('prompt.suggest', () => ({ isShown: true }))
  on('prompt.edit', (_, e) => ({ text: e.inputText, cursor: e.inputText.length }))

  for (const surface of SURFACES) {
    await $.prompt.suggest({ text: 'go', origin: ENGINE })
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ key: 'next-step' })).toBeDefined()
    await box($).edit({ origin: { kind: 'composer' }, text: '', cursor: 0, start: 0, end: 0, inputText: 'g' })
    expect(await ui.find({ key: 'next-step' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a recalled history entry takes the button away', async ($, on) => {
  on('prompt.suggest', () => ({ isShown: true }))
  on('prompt.change', (_, e) => ({ text: e.text }))

  await $.prompt.suggest({ text: 'go', origin: ENGINE })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await box($).change({ text: 'an old prompt', cursor: 13, origin: { kind: 'history' } })
  expect(await ui.find({ key: 'next-step' })).toBeUndefined()
  await ui.unmount()
})

test('a turn the box did not send, a message from another session, keeps the button', async ($, on) => {
  on('prompt.suggest', () => ({ isShown: true }))
  on('prompt.submit', (_, e) => ({ text: e.text }))

  await $.prompt.suggest({ text: 'go', origin: ENGINE })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await box($).submit({ text: 'orchestrator: drive 837', origin: { kind: 'peer' }, wait: false })
  expect(await ui.find({ key: 'next-step' })).toBeDefined()
  await box($).submit({ text: 'go on', origin: { kind: 'composer' }, wait: false })
  expect(await ui.find({ key: 'next-step' })).toBeUndefined()
  await ui.unmount()
})

test('the box keeps no ghost text of its own while the button carries the line', async ($, on) => {
  on('prompt.suggest', () => ({ isShown: true }))

  expect(await $.prompt.suggest({ text: 'go', origin: ENGINE })).toEqual({ isShown: false })
})

test('a long suggestion is cut with an ellipsis to fit the band, and a press still sends all of it', async ($, on) => {
  const sent: string[] = []
  on('prompt.submit', (_, e) => {
    sent.push(e.text)
    return { text: e.text }
  })
  const text = 'end t642 and t455 if nothing uncommitted, then drive the rest of the stack'

  await $.prompt.suggest({ text, origin: ENGINE })
  const ui = await $.ui.mount({ ...BAND, props: { ...BAND.props, bodyColumns: 30 }, surface: 'terminal' })
  const button = await ui.find({ key: 'next-step' })
  expect(button?.text).toBe('end t642 and t455 if…')
  await ui.press({ key: 'next-step' })
  expect(sent).toEqual([text])
  await ui.unmount()
})

test('a blank suggestion draws nothing', async ($) => {
  await $.prompt.suggest({ text: '  ', origin: ENGINE })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ key: 'next-step' })).toBeUndefined()
  await ui.unmount()
})

const card = (id: number, status: string, repo: string, claimed_by: string | null = null) => ({ id, status, repo, claimed_by })
const BOARD = {
  auto: { on: true, cap: 6, repo_caps: { arena: 2 } },
  tickets: [card(908, 'todo', 'arena'), card(910, 'todo', 'arena'), card(911, 'todo', 'tlon', '%9'), card(912, 'todo', 'tlon'), card(1, 'doing', 'arena', '%1'), card(2, 'doing', 'arena', '%2')],
  plan: { next: [{ ticket: 908 }] },
  needs_you: [] as unknown[],
}

// An orchestrator pane over the given board. `offer` ends a turn with the given reply, then asks for a suggestion and returns the button's text; `ran` is what a click ran.
const orchestrator = async ($: Engine, on: On, board: object) => {
  const ran: string[][] = []
  const sent: string[] = []
  on('session.start', (_, e) => e)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('prompt.submit', (_, e) => {
    sent.push(e.text)
    return { text: e.text }
  })
  on('process.run', (_, e) => {
    const joined = e.argv.join(' ')
    if (joined.includes('tmux')) return { value: { exitCode: 0, stdout: 'orchestrator\n', stderr: '' } } as never
    if (joined.includes('board.json')) return { value: { exitCode: 0, stdout: JSON.stringify(board), stderr: '' } } as never
    ran.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '' } } as never
  })
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  const offer = async (reply: string, suggestion = 'claude code suggests this') => {
    await $.turn.complete({ turnId: 't', reason: 'answer', answer: reply } as never)
    await $.prompt.suggest({ text: suggestion, origin: ENGINE })
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    const button = await ui.find({ key: 'next-step' })
    if (button !== undefined) await ui.press({ key: 'next-step' })
    await ui.unmount()
    return button?.text
  }
  return { offer, ran, sent }
}

test('on the orchestrator, the button is its own next: line, not Claude Code suggestion', async ($, on) => {
  const { offer } = await orchestrator($, on, BOARD)
  expect(await offer('Landed #5.\nnext: look at what just landed')).toBe('look at what just landed')
})

test('on the orchestrator, next: none and a reply with no line show nothing', async ($, on) => {
  const { offer } = await orchestrator($, on, BOARD)
  expect(await offer('All quiet.\nnext: none')).toBeUndefined()
  expect(await offer('All quiet.')).toBeUndefined()
})

test('on the orchestrator, a next: start for a ticket in next, a claimed one, or one over its repo cap is never offered', async ($, on) => {
  const { offer } = await orchestrator($, on, BOARD)
  for (const id of [908, 911, 910]) expect(await offer(`next: start #${id}`)).toBeUndefined()
})

test('on the orchestrator, a next: start for a free todo ticket outside next is offered', async ($, on) => {
  const { offer } = await orchestrator($, on, BOARD)
  expect(await offer('next: start #912')).toBe('start #912')
})

test('on the orchestrator with auto off, a next: start for a ticket in next is offered', async ($, on) => {
  const { offer } = await orchestrator($, on, { ...BOARD, auto: { ...BOARD.auto, on: false }, plan: { next: [{ ticket: 912 }] } })
  expect(await offer('next: start #912')).toBe('start #912')
})

test('on the orchestrator, a line naming a ticket goes to its card and types nothing', async ($, on) => {
  const { offer, ran } = await orchestrator($, on, BOARD)
  expect(await offer('next: try #912')).toBe('try #912')
  expect(ran).toEqual([['arena', 'board', '912']])
})

test('on the orchestrator, a line naming a proposal opens the inbox', async ($, on) => {
  const { offer, ran } = await orchestrator($, on, BOARD)
  expect(await offer('next: go on proposal 7')).toBe('go on proposal 7')
  expect(ran).toEqual([['arena', 'inbox']])
})

test('on the orchestrator, any other line is sent as the human, whatever waits on them', async ($, on) => {
  const board = { ...BOARD, needs_you: [{ kind: 'try', ticket: 922, text: 'try the pane' }] }
  const { offer, ran, sent } = await orchestrator($, on, board)
  expect(await offer('next: yes, cut the strip')).toBe('yes, cut the strip')
  expect(sent).toEqual(['yes, cut the strip'])
  expect(ran).toEqual([])
})

test('on the orchestrator, a line naming a ticket the board no longer has is hidden', async ($, on) => {
  const { offer } = await orchestrator($, on, BOARD)
  expect(await offer('next: try #999')).toBeUndefined()
})

test('another pane keeps the suggestion whatever the board says', async ($, on) => {
  on('prompt.suggest', () => ({ isShown: true }))
  await $.prompt.suggest({ text: 'start #908', origin: ENGINE })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ key: 'next-step' }))?.text).toBe('start #908')
  await ui.unmount()
})
