import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { item, nextLine, parseBoard, startable } from './board'

const suggestion = atom({ plugin: 'next-step', key: 'suggestion' } as const, null)

const PREFIX = 'next '
const OPTION_SEPARATOR = ' | '
const ORCHESTRATOR_SESSION = 'orchestrator'

type Option = { label: string; text: string | null; argv: string[] | null }

const choose = async ($: Parameters<typeof update>[0] & { prompt: { submit: (e: { text: string; asUser: true }) => Promise<unknown> }; process: { run: (argv: string[]) => Promise<unknown> } }, option: Option) => {
  await update($, suggestion, () => null)
  if (option.argv !== null) await $.process.run(option.argv)
  else await $.prompt.submit({ text: option.text ?? option.label, asUser: true })
}

export const register: Register = on => {
  let isOrchestrator = false

  on('session.start', async ($, e, next) => {
    const named = await $.process.run(['sh', '-c', 'tmux display-message -p -t "$TMUX_PANE" "#{session_name}"'])
    isOrchestrator = named.exitCode === 0 && named.stdout.trim() === ORCHESTRATOR_SESSION
    return next(e)
  })

  let orchestratorLine: string | null = null

  on('turn.complete', async (_, e, next) => {
    if (isOrchestrator && e.agentId === undefined) orchestratorLine = nextLine(e.answer)
    return next(e)
  })

  // The button carries the suggestion, so the box's own ghost text is held back.
  // On the orchestrator's pane the suggestion is the orchestrator's own `next:` line, not Claude Code's;
  // an option the board no longer allows is dropped; one naming a board item goes to it instead of being typed.
  // A line with ` | ` is a choice, one option each, the first recommended; a board item is never split.
  on('prompt.suggest', async ($, e) => {
    const line = isOrchestrator ? orchestratorLine : e.text.trim() === '' ? null : e.text
    const parts = line === null ? [] : isOrchestrator && item(line) === null ? line.split(OPTION_SEPARATOR).map(p => p.trim()).filter(p => p !== '') : [line]
    let shown = parts.map(p => ({ label: p, text: p, argv: isOrchestrator ? (item(p)?.argv ?? null) : null }))
    if (isOrchestrator && shown.length > 0) {
      const file = await $.process.run(['sh', '-c', 'cat "$XDG_RUNTIME_DIR/babylon/board.json"'])
      const board = file.exitCode === 0 ? parseBoard(file.stdout) : null
      if (board !== null) shown = shown.filter(o => startable(o.text, board))
    }
    await update($, suggestion, () => (shown.length === 0 ? null : shown))
    return { isShown: false }
  })

  let isBandHidden = false

  // Alt+1…9 press the Nth button, only while a choice is on screen; bare digits always type.
  on('prompt.edit', async ($, e, next) => {
    const digit = e.key?.meta === true && /^[1-9]$/.test(e.key.key) ? Number(e.key.key) : 0
    if (digit === 0) {
      await update($, suggestion, () => null)
      return next(e)
    }
    const options = await read($, suggestion)
    const chosen = options !== null && options.length > 1 && !isBandHidden ? options[digit - 1] : undefined
    if (chosen !== undefined) await choose($, chosen)
    return { text: e.text, cursor: e.cursor }
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
    const shown = await read($, suggestion)
    isBandHidden = e.props.hasSurvey || e.props.isWorking
    if (shown === null || isBandHidden) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)

    if (shown.length > 1) {
      return (
        <Box flexWrap="wrap">
          <Text dimColor>{PREFIX}</Text>
          {shown.map((o, i) => (
            <Box key={`next-step-${i}`} marginRight={1}>
              <Button key={`next-step-${i}`} variant={i === 0 ? 'primary' : undefined} label={o.label} onPress={() => choose($, o)} />
            </Box>
          ))}
        </Box>
      )
    }

    // "next " before it, "[ " and " ]" around it.
    const room = Math.max(1, e.props.bodyColumns - PREFIX.length - 4)
    const label = [...shown[0].label].length > room ? `${[...shown[0].label].slice(0, room - 1).join('')}…` : shown[0].label

    return (
      <Box>
        <Text dimColor>{PREFIX}</Text>
        <Button key="next-step" variant="primary" label={label} onPress={() => choose($, shown[0])} />
      </Box>
    )
  })
}
