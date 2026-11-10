import type { ClientModule, JsonValue } from 'claude-code'

import type { Run } from './changes'

export type List = 'files' | 'commits'
export type Input = { n: number; key?: string; shift?: true; row?: number; list?: List }
export type Section = {
  head: string
  isFocused: boolean
  first: number
  empty: string
  rows: { label: string; adds: string; dels: string; isSelected: boolean }[]
}
export type ViewProps = {
  title: string
  isFollowing: boolean
  rows: Run[][]
  diffRows: number
  note: string
  files: Section
  commits: Section
  hint: string
  acked: number
}
type Queue = { inputs: Input[]; n: number; acked: number; props: ViewProps }

const shown = (section: Section) => Math.max(1, section.rows.length)

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
    surface.onKey(({ key, shift }) => send({ key, ...(shift && { shift }) }))
    surface.onPointer(({ type, y }) => {
      if (type !== 'down') return
      const { diffRows, files, commits } = queue.props
      // title, diff and the files head sit above the files; the commits head follows them
      const inFiles = y - (diffRows + 2)
      const inCommits = inFiles - shown(files) - 1
      if (inFiles >= 0 && inFiles < files.rows.length) send({ list: 'files', row: files.first + inFiles })
      else if (inCommits >= 0 && inCommits < commits.rows.length) send({ list: 'commits', row: commits.first + inCommits })
    })
  }

  const list = (section: Section) => (
    <Box flexDirection="column">
      <Text bold={section.isFocused} dimColor={!section.isFocused} wrap="truncate-end">{section.head}</Text>
      {section.rows.length === 0 ? <Text dimColor wrap="truncate-end">{section.empty}</Text> : null}
      {section.rows.map(({ label, adds, dels, isSelected }) => (
        <Text inverse={isSelected && section.isFocused} bold={isSelected && !section.isFocused} wrap="truncate-end">
          {label}
          <Text color="success">{adds}</Text>
          <Text color="error">{dels}</Text>
        </Text>
      ))}
    </Box>
  )

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
      {list(props.files)}
      {list(props.commits)}
      <Text dimColor wrap="truncate-end">{props.hint}</Text>
    </Box>
  )
}

export default View
