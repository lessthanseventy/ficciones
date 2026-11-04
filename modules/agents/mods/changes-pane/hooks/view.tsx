import type { ClientModule, JsonValue } from 'claude-code'

import type { Run } from './changes'

export type Input = { n: number; key?: string; shift?: true; row?: number }
export type ViewProps = {
  title: string
  isFollowing: boolean
  rows: Run[][]
  diffRows: number
  note: string
  divider: string
  files: { label: string; adds: string; dels: string; isSelected: boolean }[]
  firstFile: number
  hint: string
  acked: number
}
type Queue = { inputs: Input[]; n: number; acked: number; listTop: number; fileCount: number; firstFile: number }

const View: ClientModule<JsonValue, Queue> = (raw, surface) => {
  const props = raw as unknown as ViewProps
  const { Box, Text } = surface.elements
  // A remount starts a new queue, while the hook's count of handled inputs carries on.
  const queue = surface.state ?? { inputs: [], n: props.acked, acked: 0, listTop: 0, fileCount: 0, firstFile: 0 }
  queue.acked = props.acked
  // title row, diff box, divider
  queue.listTop = 1 + props.diffRows + 1
  queue.fileCount = props.files.length
  queue.firstFile = props.firstFile

  if (!surface.state) {
    surface.setState(queue)
    // A post replaces any still undelivered this frame, so each one carries every unacknowledged input.
    const send = (input: Omit<Input, 'n'>) => {
      queue.n += 1
      queue.inputs = [...queue.inputs.filter(i => i.n > queue.acked), { ...input, n: queue.n }]
      surface.post({ inputs: queue.inputs } as unknown as JsonValue)
    }
    surface.onKey(({ key, shift }) => send({ key, ...(shift && { shift }) }))
    surface.onPointer(({ type, y }) => {
      const row = y - queue.listTop
      if (type === 'down' && row >= 0 && row < queue.fileCount) send({ row: queue.firstFile + row })
    })
  }

  return (
    <Box flexDirection="column">
      <Box justifyContent="space-between">
        <Text bold wrap="truncate-end">{props.title}</Text>
        {props.isFollowing ? <Text color="success">● following</Text> : <Text dimColor>○ held</Text>}
      </Box>
      <Box height={props.diffRows} overflow="hidden" flexDirection="column">
        {props.note ? <Text dimColor>{props.note}</Text> : null}
        {props.rows.map(row => (
          <Text wrap="truncate-end">
            {row.map(r => (
              <Text color={r.c} backgroundColor={r.b} bold={r.bold} dimColor={r.dim} italic={r.it} underline={r.u}>
                {r.t}
              </Text>
            ))}
          </Text>
        ))}
      </Box>
      <Text dimColor>{props.divider}</Text>
      {props.files.map(({ label, adds, dels, isSelected }) => (
        <Text inverse={isSelected} wrap="truncate-end">
          {label}
          <Text color="success">{adds}</Text>
          <Text color="error">{dels}</Text>
        </Text>
      ))}
      <Text dimColor wrap="truncate-end">{props.hint}</Text>
    </Box>
  )
}

export default View
