// node --test lib/clock-core.test.mjs (mise shell:test): the pure half of the rail clock. The
// faces are literals: the office kit's modules import each other bundler-style, which node cannot load.
import { test } from "node:test"
import assert from "node:assert/strict"
import { railLines } from "./clock-core.ts"

test("the rail clock is the plain time, stacked", () => {
  assert.deepEqual(railLines("14:30"), ["14", "30"])
  assert.deepEqual(railLines("00:05"), ["00", "05"])
})

test("a joke face takes the first line alone", () => {
  assert.deepEqual(railLines("404"), ["404", ""])
  assert.deepEqual(railLines("π"), ["π", ""])
})
