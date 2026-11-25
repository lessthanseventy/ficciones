import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

const suggestion = atom({ plugin: 'next-step', key: 'suggestion' } as const, null)

const PREFIX = 'next '

export const register: Register = on => {
  // The button carries the suggestion, so the box's own ghost text is held back.
  on('prompt.suggest', async ($, e) => {
    if (e.text.trim() === '') return { isShown: false }
    await update($, suggestion, () => e.text)
    return { isShown: false }
  })

  on('prompt.edit', async ($, e, next) => {
    await update($, suggestion, () => null)
    return next(e)
  })

  on('prompt.change', async ($, e, next) => {
    await update($, suggestion, () => null)
    return next(e)
  })

  // A turn the box did not send (another session's message, a task's notice) leaves the button up.
  on('prompt.submit', { origin: { kind: 'composer' } }, async ($, e, next) => {
    await update($, suggestion, () => null)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const text = await read($, suggestion)
    if (text === null || e.props.hasSurvey || e.props.isWorking) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const send = async () => {
      await update($, suggestion, () => null)
      await $.prompt.submit({ text, asUser: true })
    }

    // "next " before it, "[ " and " ]" around it.
    const room = Math.max(1, e.props.bodyColumns - PREFIX.length - 4)
    const label = [...text].length > room ? `${[...text].slice(0, room - 1).join('')}…` : text

    return (
      <Box>
        <Text dimColor>{PREFIX}</Text>
        <Button key="next-step" variant="primary" label={label} onPress={send} />
      </Box>
    )
  })
}
