import type { ClientModule, JsonValue } from 'claude-code'

import type { Key, Run } from './frame'

type Props = { rows: Run[][]; hint: string; acked: number }
type Queue = { keys: (Key & { n: number })[]; n: number; acked: number }

const Terminal: ClientModule<JsonValue, Queue> = (raw, surface) => {
  const props = raw as unknown as Props
  const { Box, Text } = surface.elements
  const queue = surface.state ?? { keys: [], n: 0, acked: 0 }
  queue.acked = props.acked

  if (!surface.state) {
    surface.setState(queue)
    surface.onKey(({ key, ctrl, shift, meta }) => {
      queue.n += 1
      // A post replaces any still undelivered this frame, so each one carries every unacknowledged key.
      queue.keys = [
        ...queue.keys.filter(k => k.n > queue.acked),
        { n: queue.n, key, ...(ctrl && { ctrl }), ...(shift && { shift }), ...(meta && { meta }) },
      ]
      surface.post({ keys: queue.keys } as unknown as JsonValue)
    })
  }

  return (
    <Box flexDirection="column">
      {props.rows.map(row => (
        <Text wrap="truncate-end">
          {row.map(r => (
            <Text
              color={r.c}
              backgroundColor={r.b}
              bold={r.bold}
              dimColor={r.dim}
              italic={r.it}
              underline={r.u}
              inverse={r.inv}
            >
              {r.t}
            </Text>
          ))}
        </Text>
      ))}
      <Text dimColor wrap="truncate-end">{props.hint}</Text>
    </Box>
  )
}

export default Terminal
