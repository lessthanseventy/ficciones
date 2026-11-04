import type { ClientModule, JsonValue } from 'claude-code'

import type { File } from './changes'

export type Input = { n: number; key?: string; shift?: true; ctrl?: true; row?: number }
export type ViewProps = {
  branch: string
  rows: { file: File; label: string; isSelected: boolean }[]
  firstRow: number
  title: string
  source: string
  path: string
  note: string
  hint: string
  diffRows: number
  acked: number
}
type Queue = { inputs: Input[]; n: number; acked: number; rowCount: number; firstRow: number }

const HEADER_ROWS = 1

const View: ClientModule<JsonValue, Queue> = (raw, surface) => {
  const props = raw as unknown as ViewProps
  const { Box, Text, Code } = surface.elements
  const queue = surface.state ?? { inputs: [], n: 0, acked: 0, rowCount: 0, firstRow: 0 }
  queue.acked = props.acked
  queue.rowCount = props.rows.length
  queue.firstRow = props.firstRow

  if (!surface.state) {
    surface.setState(queue)
    // A post replaces any still undelivered this frame, so each one carries every unacknowledged input.
    const send = (input: Omit<Input, 'n'>) => {
      queue.n += 1
      queue.inputs = [...queue.inputs.filter(i => i.n > queue.acked), { ...input, n: queue.n }]
      surface.post({ inputs: queue.inputs } as unknown as JsonValue)
    }
    surface.onKey(({ key, ctrl, shift }) => send({ key, ...(ctrl && { ctrl }), ...(shift && { shift }) }))
    surface.onPointer(({ type, y }) => {
      const row = y - HEADER_ROWS
      if (type === 'down' && row >= 0 && row < queue.rowCount) send({ row: queue.firstRow + row })
    })
  }

  return (
    <Box flexDirection="column">
      <Box justifyContent="space-between">
        <Text bold>changes</Text>
        <Text color="suggestion">{props.branch}</Text>
      </Box>
      {props.rows.map(({ file, label, isSelected }) => (
        <Text inverse={isSelected} wrap="truncate-end">
          <Text color="success">{file.x}</Text>
          <Text color="error">{file.y}</Text>
          {` ${label}`}
        </Text>
      ))}
      {props.note ? <Text dimColor>{props.note}</Text> : null}
      <Text dimColor wrap="truncate-end">{props.title}</Text>
      <Box height={props.diffRows} overflow="hidden" flexDirection="column">
        {props.source ? <Code source={props.source} path={props.path} format="diff" wrap="truncate-end" /> : <Text dimColor>no diff to show</Text>}
      </Box>
      <Text dimColor wrap="truncate-end">{props.hint}</Text>
    </Box>
  )
}

export default View
