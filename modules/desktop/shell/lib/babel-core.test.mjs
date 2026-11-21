// node --test lib/babel-core.test.mjs (mise shell:test): the pure half of lib/babel.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { FOUND, foundLines } from "./babel-core.ts"

const draws = (...xs) => { let i = 0; return () => xs[i++] }

test("the usual page holds nothing", () => {
  assert.equal(foundLines(40, draws(0.5)), null)
})

test("a found sentence is wrapped to the page's width", () => {
  assert.deepEqual(foundLines(80, draws(0, 0)), [FOUND[0]])
  assert.deepEqual(foundLines(16, draws(0, 0)), ["somewhere in", "these rooms is", "the book of you"])
})
