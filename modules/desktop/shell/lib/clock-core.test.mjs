// node --test lib/clock-core.test.mjs (mise shell:test): the pure half of the rail clock, over the
// office kit's own clockFace.
import { test } from "node:test"
import assert from "node:assert/strict"
import { clockFace } from "../office/kit/eggs.ts"
import { railLines } from "./clock-core.ts"

const lines = (h, m) => railLines(clockFace(new Date(2026, 9, 19, h, m)))

test("the rail clock is the plain time, stacked", () => {
  assert.deepEqual(lines(14, 30), ["14", "30"])
  assert.deepEqual(lines(0, 5), ["00", "05"])
})

test("it cannot find the time at 4:04 and is irrational at 3:14", () => {
  assert.deepEqual(lines(4, 4), ["404", ""])
  assert.deepEqual(lines(16, 4), ["404", ""])
  assert.deepEqual(lines(15, 14), ["π", ""])
})
