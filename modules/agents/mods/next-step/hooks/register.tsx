import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { nextLine, parseBoard, startable, waiting } from './board'

const suggestion = atom({ plugin: 'next-step', key: 'suggestion' } as const, null)

const PREFIX = 'next '
const ORCHESTRATOR_SESSION = 'orchestrator'

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
  // what waits on the human comes first, and a start the board no longer allows is dropped.
  on('prompt.suggest', async ($, e) => {
    const line = isOrchestrator ? orchestratorLine : e.text.trim() === '' ? null : e.text
    let shown: { label: string; text: string | null; argv: string[] | null } | null = line === null ? null : { label: line, text: line, argv: null }
    if (isOrchestrator) {
      const file = await $.process.run(['sh', '-c', 'cat "$XDG_RUNTIME_DIR/babylon/board.json"'])
      const board = file.exitCode === 0 ? parseBoard(file.stdout) : null
      if (board !== null) {
        const waits = waiting(board)
        if (waits !== null) shown = { label: waits.label, text: null, argv: waits.ticket === null ? ['arena', 'inbox'] : ['arena', 'board', String(waits.ticket)] }
        else if (line !== null && !startable(line, board)) shown = null
      }
    }
    await update($, suggestion, () => shown)
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
    const shown = await read($, suggestion)
    if (shown === null || e.props.hasSurvey || e.props.isWorking) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const send = async () => {
      await update($, suggestion, () => null)
      if (shown.argv !== null) await $.process.run(shown.argv)
      else await $.prompt.submit({ text: shown.text ?? shown.label, asUser: true })
    }

    // "next " before it, "[ " and " ]" around it.
    const room = Math.max(1, e.props.bodyColumns - PREFIX.length - 4)
    const label = [...shown.label].length > room ? `${[...shown.label].slice(0, room - 1).join('')}…` : shown.label

    return (
      <Box>
        <Text dimColor>{PREFIX}</Text>
        <Button key="next-step" variant="primary" label={label} onPress={send} />
      </Box>
    )
  })
}
