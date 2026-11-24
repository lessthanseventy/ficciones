import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

const suggestion = atom({ plugin: 'next-step', key: 'suggestion' } as const, null)

export const register: Register = on => {
  on('prompt.suggest', async ($, e, next) => {
    const shown = await next(e)
    if (shown.isShown) await update($, suggestion, () => e.text)
    return shown
  })

  on('prompt.edit', async ($, e, next) => {
    await update($, suggestion, () => null)
    return next(e)
  })

  on('prompt.change', async ($, e, next) => {
    await update($, suggestion, () => null)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
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

    return (
      <Box>
        <Text dimColor>next </Text>
        <Button key="next-step" label={text} onPress={send} />
      </Box>
    )
  })
}
