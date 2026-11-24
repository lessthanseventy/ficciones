import { expect, test } from 'claude-code/testing'
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

test('a suggestion the box did not show draws nothing', async ($, on) => {
  on('prompt.suggest', () => ({ isShown: false }))

  await $.prompt.suggest({ text: 'go', origin: ENGINE })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ key: 'next-step' })).toBeUndefined()
  await ui.unmount()
})
