// node --test lib/xwd-core.test.mjs (mise shell:test): finding the pixels in an Xvfb screen file.
import { test } from "node:test"
import assert from "node:assert/strict"
import { xwdFrame } from "./xwd-core.ts"

// Xvfb's own header for a 400x300x24 screen: 160 bytes, 256 colormap entries
function screen({ w = 400, h = 300, order = 0, bpp = 32, short = 0 } = {}) {
  const header = 160, ncolors = 256, stride = w * 4
  const b = new Uint8Array(header + ncolors * 12 + stride * h - short)
  const v = new DataView(b.buffer)
  const set = (i, x) => v.setUint32(i * 4, x)
  set(0, header); set(1, 7); set(2, 2); set(3, 24); set(4, w); set(5, h); set(7, order)
  set(11, bpp); set(12, stride); set(19, ncolors)
  return b
}

test("the pixels start past the header and the colormap", () => {
  assert.deepEqual(xwdFrame(screen()), { offset: 160 + 256 * 12, width: 400, height: 300, stride: 1600 })
})

test("a layout the texture cannot take is refused", () => {
  assert.equal(xwdFrame(screen({ order: 1 })), null)
  assert.equal(xwdFrame(screen({ bpp: 16 })), null)
})

test("a file shorter than its frame is refused", () => {
  assert.equal(xwdFrame(screen({ short: 1 })), null)
  assert.equal(xwdFrame(new Uint8Array(10)), null)
})
