import type { Register } from 'claude-code'

import { callText, menardSaid, shellEdits, took, turnLine, whyFailed } from './calls'
import type { Call } from './calls'

// Fewer calls than this and the turn's own rows say it; more lines than the cap and the oldest go.
const MIN_TURN_CALLS = 4
const MAX_TURN_LINES = 80
const SUMMARY_MS = 8000
const SUMMARISE = 'Below are the tool calls a coding assistant made in one turn, in order, each with how it ended where that is known. Say what was done in one or two plain sentences, 45 words at most: which files changed and how, what was run, and whether it passed. Start each sentence with its verb ("Edited…", "Ran…"), never "I". No preamble, no markdown, no line breaks.\n\n'
// A turn's summary is drawn under its closing line, which is known by its duration alone.
const MAX_KEPT_SUMMARIES = 50
const MAX_GROUP_LINES = 12
const MAX_KEPT_DURATIONS = 2000

// The calls drawn as one line each; any other tool keeps Claude Code's own row.
const ROWED = new Set(['Bash', 'Read', 'Edit', 'Write', 'Grep', 'Glob'])

type Ui = { ui: { resolve: (e: never) => Record<string, any>; invalidate: (event: string) => void } }

// One call's line and, once clicked, the call as it was made and answered under it. A click on
// the line or anywhere in the opened text folds it: the text is a view of its own (body.tsx).
function callRow($: Ui, e: unknown, opened: Set<string>, id: string, call: Call, line: string, time: string) {
  const { Box, Text, Button, Client } = $.ui.resolve(e as never)
  const isOpen = opened.has(id)
  const toggle = () => {
    if (!opened.delete(id)) opened.add(id)
    $.ui.invalidate('ui.render')
  }
  const space = line.indexOf(' ')
  const files = call.tool === 'Bash' ? shellEdits(call.output) : []
  const why = line.includes(' (failed)') ? whyFailed(call.output) : ''
  const body = space < 0 ? '' : line.slice(space)
  const arrow = body.indexOf(' → ')
  const made = arrow < 0 ? body : body.slice(0, arrow)
  const counted = call.tool === 'Edit' || call.tool === 'Write' ? made.match(/^(.*) (\+\d+) (-\d+)(.*)$/) : null
  const failing = (text: string) =>
    text.split(/( \((?:failed|running)\))/).map(part =>
      part === ' (failed)' ? <Text color="error">{part}</Text> : part === ' (running)' ? <Text color="warning">{part}</Text> : part,
    )
  // the lead stands in a column of its own, so a line that wraps comes back under its text
  return (
    <Box>
      <Text>{'  '}</Text>
      <Button plain key={`fold-${id}`} onPress={toggle}>
        <Text color="claude">{isOpen ? '▼' : '▶'}</Text>
      </Button>
      <Text>{'  '}</Text>
      <Box flexShrink={1} flexDirection="column">
        <Button plain key={`call-${id}`} onPress={toggle}>
          <Text color="remember">{space < 0 ? line : line.slice(0, space)}</Text>
          {failing(counted ? counted[1]! : made)}
          {counted ? <Text color="success">{` ${counted[2]}`}</Text> : null}
          {counted ? <Text color="error">{` ${counted[3]}`}</Text> : null}
          {counted ? failing(counted[4]!) : null}
          {arrow < 0 ? null : <Text color="suggestion">{body.slice(arrow)}</Text>}
          {time ? <Text color="claude">{`  ${time}`}</Text> : null}
        </Button>
        {why ? (
          <Box paddingLeft={2}>
            <Text color="error">{why}</Text>
          </Box>
        ) : null}
        {files.length > 0 ? (
          <Box paddingLeft={2}>
            <Text>
              <Text dimColor>✎ </Text>
              {files.map(({ name, adds, dels }, index) => (
                <Text>
                  {index > 0 ? <Text dimColor> · </Text> : null}
                  {name} <Text color="success">+{adds}</Text> <Text color="error">-{dels}</Text>
                </Text>
              ))}
            </Text>
          </Box>
        ) : null}
        {isOpen ? <Client key={`body-${id}`} module="./body.tsx" props={{ id, lines: callText(call) }} width="100%" /> : null}
      </Box>
    </Box>
  )
}

export const register: Register = on => {
  let canDraw = false
  let turnLines: string[] = []
  const summaries = new Map<number, string>()
  const opened = new Set<string>()
  const ours = new Set<string>()
  const replies = new Map<string, unknown>()
  const durations = new Map<string, number>()

  // VS Code and mobile draw a call their own way
  on('session.start', async ($, e, next) => {
    canDraw = e.surface === 'terminal' || e.surface === 'desktop'
    // a resumed session draws its old turns again, each still known by its duration
    const kept = await $.store.get('summaries')
    if (Array.isArray(kept)) for (const [durationMs, text] of kept as [number, string][]) summaries.set(durationMs, text)
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) turnLines = []
    return next(e)
  })

  // One line under a long turn's answer, from a small model, of what the turn's calls came to.
  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId !== undefined) return done
    const lines = turnLines
    turnLines = []
    if (!canDraw || e.reason !== 'answer' || lines.length < MIN_TURN_CALLS) return done
    // not awaited: the turn ends now and the line arrives under it
    void $.model.complete({ model: 'haiku', prompt: SUMMARISE + lines.join('\n'), maxTokens: 200, effort: 'low', timeoutMs: SUMMARY_MS }).then(reply => {
      if (!reply.isAnswered) return
      if (summaries.size >= MAX_KEPT_SUMMARIES) summaries.clear()
      summaries.set(e.durationMs, reply.text.trim().replace(/\s+/g, ' '))
      void $.store.set('summaries', [...summaries])
      $.ui.invalidate('ui.render')
    })
    return done
  })

  on('ui.render', { component: 'TurnDuration' }, async ($, e, next) => {
    const summary = summaries.get(e.props.durationMs)
    if (summary === undefined) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {await next(e)}
        <Box flexDirection="column" borderStyle="round" borderColor="remember" borderDimColor paddingX={1} marginLeft={2}>
          <Text weight="bold" color="remember">turn</Text>
          <Text color="suggestion">{summary}</Text>
        </Box>
      </Box>
    )
  })

  on('tool.call', async ($, e, next) => {
    const started = Date.now()
    const result = await next(e)
    const id = (e as { tool_use_id?: string }).tool_use_id
    if (id !== undefined) {
      if (durations.size >= MAX_KEPT_DURATIONS) durations.clear()
      durations.set(id, Date.now() - started)
      $.ui.invalidate('ui.render')
    }
    if ((e as { agentId?: string }).agentId === undefined) {
      const call = { tool: e.tool, input: e, output: (result as { result?: unknown }).result }
      const edited = shellEdits(call.output).map(({ name, adds, dels }) => ` · ${name} +${adds} -${dels}`).join('')
      turnLines = [...turnLines, turnLine(call, (result as { isError?: boolean }).isError === true) + edited].slice(-MAX_TURN_LINES)
    }
    return result
  })

  // A call is one line of what it was and how it went, in place of the call as typed and its
  // output; a click opens that one call and folds it again.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const input = e.props.input as { run_in_background?: boolean } | undefined
    const isRowed = ROWED.has(e.props.tool) || menardSaid(e.props) !== null
    if (!canDraw || e.props.isExpanded || !isRowed || input?.run_in_background === true) return next(e)
    const id = e.props.tool_use_id
    ours.add(id)
    const call = { ...e.props, output: e.props.output ?? replies.get(id) }
    const line = turnLine(call, e.props.isErrored === true || e.props.isInterrupted === true)
    // a call still being written or waiting on a permission has no arguments to name yet
    return callRow($, e, opened, id, call, e.props.isRunning || line === e.props.tool ? `${line} (running)` : line, took(durations.get(id)))
  })

  // A result's own props do not say what ran, so the calls a line was drawn for are kept by id.
  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => {
    if (!canDraw || e.props.isExpanded || !ours.has(e.props.tool_use_id)) return next(e)
    replies.set(e.props.tool_use_id, e.props.output)
    const { Box } = $.ui.resolve(e)
    return <Box />
  })

  // A folded run of calls is a line for each, in the order they were made, in place of the
  // count: this hook answers for the whole run and does not pass it on.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    if (!canDraw || e.props.isExpanded) return next(e)
    const calls = e.props.calls.map((call, index) => ({ call, id: call.tool_use_id ?? `group-${index}` }))
    // a run that holds more than its calls (a recalled memory) keeps Claude Code's line above
    // the rows; when the more is a failed call's own lines, its row here says it
    const isWhole = e.props.isCallsOnly === true || calls.some(({ call }) => call.isErrored === true)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {isWhole ? null : await next(e)}
        {calls.slice(0, MAX_GROUP_LINES).map(({ call, id }) =>
          callRow($, e, opened, id, call, `${turnLine(call, call.isErrored === true)}${call.isRunning || call.input === undefined ? ' (running)' : ''}`, took(durations.get(id))),
        )}
        {calls.length > MAX_GROUP_LINES ? <Text dimColor>{`     … ${calls.length - MAX_GROUP_LINES} more calls`}</Text> : null}
      </Box>
    )
  })

  // an opened call's text was clicked
  on('ui.message', async ($, e, next) => {
    const fold = (e.data as { fold?: unknown } | null)?.fold
    if (typeof fold !== 'string') return next(e)
    opened.delete(fold)
    $.ui.invalidate('ui.render')
    return {}
  })
}
