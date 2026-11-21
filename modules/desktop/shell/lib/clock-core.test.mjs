// node --test lib/clock-core.test.mjs (mise shell:test): the pure half of the rail clock.
import { test } from "node:test"
import assert from "node:assert/strict"
import { clockFace, railLines } from "./clock-core.ts"

test("the face is the plain time, but for its jokes", () => {
  assert.equal(clockFace(new Date(2026, 10, 21, 14, 30)), "14:30")
  assert.equal(clockFace(new Date(2026, 10, 21, 0, 5)), "00:05")
  assert.equal(clockFace(new Date(2026, 10, 21, 16, 4)), "404")
  assert.equal(clockFace(new Date(2026, 10, 21, 3, 14)), "π")
  assert.equal(clockFace(new Date(2026, 2, 14, 9, 0, 10)), "3.14")
  assert.equal(clockFace(new Date(2026, 2, 14, 9, 0, 40)), "09:00")
})

test("the rail clock is the plain time, stacked", () => {
  assert.deepEqual(railLines("14:30"), ["14", "30"])
  assert.deepEqual(railLines("00:05"), ["00", "05"])
})

test("a joke face takes the first line alone", () => {
  assert.deepEqual(railLines("404"), ["404", ""])
  assert.deepEqual(railLines("π"), ["π", ""])
})
