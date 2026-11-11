import type { ClientModule, JsonValue, RenderChildren } from 'claude-code'

import type { Run } from './changes'

// A click: on a row of the files' list, on a row of the diff, or anywhere else, which only asks for the keys.
export type Input = { n: number; row?: number; diff?: number }
export type Section = {
  head: string
  rule: string
  isFocused: boolean
  first: number
  empty: string
  rows: { lead: string; dim: string; label: string; adds: string; dels: string; isSelected: boolean }[]
}
export type ViewProps = {
  title: string
  where: string
  adds: string
  dels: string
  rule: string
  columns: number
  rows: Run[][]
  diffRows: number
  note: string
  files: Section
  acked: number
}
type Queue = { inputs: Input[]; n: number; acked: number; props: ViewProps }

const View: ClientModule<JsonValue, Queue> = (raw, surface) => {
  const props = raw as unknown as ViewProps
  const { Box, Text } = surface.elements
  // A remount starts a new queue, while the hook's count of handled inputs carries on.
  const queue = surface.state ?? { inputs: [], n: props.acked, acked: 0, props }
  queue.acked = props.acked
  queue.props = props

  if (!surface.state) {
    surface.setState(queue)
    // A post replaces any still undelivered this frame, so each one carries every unacknowledged input.
    const send = (input: Omit<Input, 'n'>) => {
      queue.n += 1
      queue.inputs = [...queue.inputs.filter(i => i.n > queue.acked), { ...input, n: queue.n }]
      surface.post({ inputs: queue.inputs } as unknown as JsonValue)
    }
    surface.onPointer(({ type, y }) => {
      if (type !== 'down') return
      const { diffRows, files, rows, note } = queue.props
      // under the box's top edge, and under the note where there is one
      const inDiff = y - 1 - (note ? 1 : 0)
      // the diff's box and the files' top edge sit above the files
      const inFiles = y - (diffRows + 3)
      if (inDiff >= 0 && inDiff < rows.length) send({ diff: inDiff })
      else if (inFiles >= 0 && inFiles < files.rows.length) send({ row: files.first + inFiles })
      else send({})
    })
  }

  const edge = (isLit: boolean) => ({ color: isLit ? 'claude' : undefined, dimColor: !isLit, weight: isLit ? ('bold' as const) : undefined })
  const bottom = `╰${'─'.repeat(props.columns)}╯`
  const within = (isLit: boolean, content: RenderChildren) => (
    <Box>
      <Text {...edge(isLit)}>│</Text>
      <Box width={props.columns}>{content}</Box>
      <Text {...edge(isLit)}>│</Text>
    </Box>
  )
  const { files } = props
  const blank = Math.max(0, props.diffRows - props.rows.length - (props.note ? 1 : 0))

  return (
    <Box flexDirection="column">
      <Box>
        <Text dimColor>{props.title === '' ? '╭──' : '╭─ '}</Text>
        <Text weight="bold" color="claude">{props.title}</Text>
        <Text dimColor>{props.where}</Text>
        <Text color="success">{props.adds}</Text>
        <Text color="error">{props.dels}</Text>
        <Text dimColor>{props.rule}╮</Text>
      </Box>
      {props.note ? within(false, <Text dimColor wrap="truncate-end">{props.note}</Text>) : null}
      {props.rows.map(row =>
        within(
          false,
          <Text wrap="truncate-end">
            {row.map(r => (
              <Text color={r.c} backgroundColor={r.b} weight={r.bold ? 'bold' : undefined} dimColor={r.dim} italic={r.it} underline={r.u}>
                {r.t}
              </Text>
            ))}
          </Text>,
        ),
      )}
      {Array.from({ length: blank }, () => within(false, <Text> </Text>))}
      <Text dimColor>{bottom}</Text>
      <Box>
        <Text {...edge(files.isFocused)}>╭─ </Text>
        <Text weight="bold" color={files.isFocused ? 'claude' : 'remember'}>{files.head}</Text>
        <Text {...edge(files.isFocused)}>{files.rule}╮</Text>
      </Box>
      {files.rows.length === 0 ? within(files.isFocused, <Text dimColor wrap="truncate-end">{files.empty}</Text>) : null}
      {files.rows.map(({ lead, dim, label, adds, dels, isSelected }) =>
        within(
          files.isFocused,
          <Text inverse={isSelected && files.isFocused} weight={isSelected && !files.isFocused ? 'bold' : undefined} wrap="truncate-end">
            <Text color="remember">{lead}</Text>
            <Text dimColor={!isSelected}>{dim}</Text>
            {label}
            <Text color="success">{adds}</Text>
            <Text color="error">{dels}</Text>
          </Text>,
        ),
      )}
      <Text {...edge(files.isFocused)}>{bottom}</Text>
    </Box>
  )
}

export default View
