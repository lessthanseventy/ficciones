// node --test lib/rotation-core.test.mjs (mise shell:test): the backdrop rotation's one pile.
import { test } from "node:test"
import assert from "node:assert/strict"
import { pickTurn } from "./rotation-core.ts"

const ambient = (name) => ({ hack: false, name })
const hack = (name) => ({ hack: true, name })

test("ambients and hacks are one pile, each entry as likely as any other", () => {
  const n = 4
  const picks = Array.from({ length: n }, (_, i) => pickTurn(["life", "rain"], ["xjack", "glmatrix"], [], () => i / n))
  assert.deepEqual(picks, [ambient("life"), ambient("rain"), hack("xjack"), hack("glmatrix")])
})

test("what any monitor is showing is not picked", () => {
  assert.deepEqual(pickTurn(["life"], ["xjack", "moire"], [ambient("life"), hack("xjack")], () => 0), hack("moire"))
})

test("an ambient and a hack of the same name are different entries", () => {
  assert.deepEqual(pickTurn(["maze"], ["maze"], [ambient("maze")], () => 0), hack("maze"))
})

test("a pile with nothing fresh repeats rather than stops", () => {
  assert.deepEqual(pickTurn(["life"], [], [ambient("life")], () => 0), ambient("life"))
})

test("an empty pile picks nothing", () => {
  assert.equal(pickTurn([], [], [], () => 0), null)
})
