import { expect, test } from 'claude-code/testing'

import { parseFrame, tmuxKey } from './frame'

test('colours carry across rows and reset', async () => {
  const [a, b] = parseFrame('\x1b[32mhi\nthere\x1b[0m x', 2)
  expect(a).toEqual([{ c: 'green', t: 'hi' }])
  expect(b).toEqual([{ c: 'green', t: 'there' }, { t: ' x' }])
})

test('256 and truecolor', async () => {
  const [a] = parseFrame('\x1b[38;5;196ma\x1b[48;2;1;2;3mb', 1)
  expect(a).toEqual([{ c: '#ff0000', t: 'a' }, { c: '#ff0000', b: '#010203', t: 'b' }])
})

test('cursor inverts its cell, past end of line too', async () => {
  expect(parseFrame('abc', 1, { x: 1, y: 0 })[0]).toEqual([{ t: 'a' }, { inv: true, t: 'b' }, { t: 'c' }])
  expect(parseFrame('a', 1, { x: 2, y: 0 })[0]).toEqual([{ t: 'a ' }, { inv: true, t: ' ' }])
})

test('keys map to tmux names', async () => {
  expect(tmuxKey({ key: 'return' })).toBe('Enter')
  expect(tmuxKey({ key: 'tab', shift: true })).toBe('BTab')
  expect(tmuxKey({ key: 'g', ctrl: true })).toBe('C-g')
  expect(tmuxKey({ key: ';' })).toBe('\;')
  expect(tmuxKey({ key: 'A', shift: true })).toBe('A')
})
