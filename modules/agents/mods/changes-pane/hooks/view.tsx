import type { ClientModule, JsonValue, RenderChildren } from 'claude-code'

import type { Run } from './changes'

export type List = 'files' | 'commits'
export type Input = { n: number; row?: number; list?: List; diff?: number }
export type Section = {
  head: string
  rule: string
  isFocused: boolean
  first: number
  empty: string
  rows: { lead: string; dim: string; label: string; adds: string; dels: string; isSelected: boolean; isAhead?: boolean }[]
}
export type ViewProps = {
  title: string
  where: string
  adds: string
  dels: string
  rule: string
  columns: number
  isFollowing: boolean
  rows: Run[][]
  diffRows: number
  note: string
  files: Section
  commits: Section
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
    // No key listener: the pane's keys are its buttons', under the focus Claude Code keeps, and a
    // click anywhere here asks for that focus.
    surface.onPointer(({ type, y }) => {
      if (type !== 'down') return
      const { diffRows, files, commits, rows, note } = queue.props
      // under the box's top edge, and under the note where there is one
      const inDiff = y - 1 - (note ? 1 : 0)
      // the diff's box and the files' top edge sit above the files; their bottom edge and the commits' top follow them
      const inFiles = y - (diffRows + 3)
      const inCommits = inFiles - shown(files) - 2
      if (inDiff >= 0 && inDiff < rows.length) send({ diff: inDiff })
      else if (inFiles >= 0 && inFiles < files.rows.length) send({ list: 'files', row: files.first + inFiles })
      else if (inCommits >= 0 && inCommits < commits.rows.length) send({ list: 'commits', row: commits.first + inCommits })
      else send({})
    })
  }

  // A box as lazygit draws one: the title in the top edge, and the edge lit when the box has the keys.
  const edge = (isLit: boolean) => ({ color: isLit ? 'claude' : undefined, dimColor: !isLit, weight: isLit ? ('bold' as const) : undefined })
  const bottom = `╰${'─'.repeat(props.columns)}╯`
  const within = (isLit: boolean, content: RenderChildren) => (
    <Box>
      <Text {...edge(isLit)}>│</Text>
      <Box width={props.columns}>{content}</Box>
      <Text {...edge(isLit)}>│</Text>
    </Box>
  )

  const list = (section: Section) => (
    <Box flexDirection="column">
      <Box>
        <Text {...edge(section.isFocused)}>╭─ </Text>
        <Text weight="bold" color={section.isFocused ? 'claude' : 'remember'}>{section.head}</Text>
        <Text {...edge(section.isFocused)}>{section.rule}╮</Text>
      </Box>
      {section.rows.length === 0 ? within(section.isFocused, <Text dimColor wrap="truncate-end">{section.empty}</Text>) : null}
      {section.rows.map(({ lead, dim, label, adds, dels, isSelected, isAhead }) =>
        within(
          section.isFocused,
          <Text inverse={isSelected && section.isFocused} weight={isSelected && !section.isFocused ? 'bold' : undefined} wrap="truncate-end">
            <Text color={isAhead ? 'error' : 'remember'}>{lead}</Text>
            <Text dimColor={!isSelected}>{dim}</Text>
            {label}
            <Text color="success">{adds}</Text>
            <Text color="error">{dels}</Text>
          </Text>,
        ),
      )}
      <Text {...edge(section.isFocused)}>{bottom}</Text>
    </Box>
  )

  const blank = Math.max(0, props.diffRows - props.rows.length - (props.note ? 1 : 0))

  return (
    <Box flexDirection="column">
      <Box>
        <Text dimColor>{props.title === '' ? '╭──' : '╭─ '}</Text>
        <Text weight="bold" color="claude">{props.title}</Text>
        <Text dimColor>{props.where}</Text>
        <Text color="success">{props.adds}</Text>
        <Text color="error">{props.dels}</Text>
        <Text dimColor>{props.rule}</Text>
        {props.isFollowing ? <Text color="success"> ● following </Text> : <Text dimColor> ○ held </Text>}
        <Text dimColor>╮</Text>
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
      {list(props.files)}
      {list(props.commits)}
    </Box>
  )
}

export default View
