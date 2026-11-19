import { expect, test } from 'claude-code/testing'

import { rowsFor } from './picture'

const head = (width: number, height: number) => {
  const b = new Uint8Array(24)
  new DataView(b.buffer).setUint32(16, width)
  new DataView(b.buffer).setUint32(20, height)
  return b
}

test('a picture keeps its shape in cells twice as tall as wide', async () => {
  expect(rowsFor(head(1920, 1080), 72)).toBe(20)
  expect(rowsFor(head(100, 100), 72)).toBe(36)
})

test('a tall picture stops at sixty rows and a flat one takes one', async () => {
  expect(rowsFor(head(100, 4000), 72)).toBe(60)
  expect(rowsFor(head(4000, 10), 72)).toBe(1)
})

test('a head with no size is no picture', async () => {
  expect(rowsFor(head(0, 100), 72)).toBeNull()
  expect(rowsFor(new Uint8Array(8), 72)).toBeNull()
})
