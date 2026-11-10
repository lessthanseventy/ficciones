import type { ClientModule, JsonValue } from 'claude-code'

export type BodyProps = { id: string; lines: string[] }

// An opened call's text. A click anywhere in it folds the call: a Button would do that too, but
// the pointer inverts a Button whole, and a screen of inverted output is unreadable.
const Body: ClientModule<JsonValue, true> = (raw, surface) => {
  const props = raw as unknown as BodyProps
  const { Box, Text } = surface.elements
  if (!surface.state) {
    surface.setState(true)
    surface.onPointer(({ type }) => {
      if (type === 'down') surface.post({ fold: props.id })
    })
  }
  return (
    <Box flexDirection="column" paddingLeft={2}>
      {props.lines.map(line => (
        <Text dimColor>{line === '' ? ' ' : line}</Text>
      ))}
    </Box>
  )
}

export default Body
