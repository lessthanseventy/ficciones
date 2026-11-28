// node --test lib/funes-core.test.mjs (mise shell:test): what a memory file may hold.
import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./funes-core.ts"

const m = { key: "ghostty", mode: "apps", title: "Ghostty", count: 3, last: 1 }

test("text that is no JSON object holds no memories", () => {
  for (const text of ["null", "[]", "3", '"x"', "", "{"]) assert.deepEqual(load(text), {})
})

test("an entry that is not a memory is dropped, the rest kept", () => {
  assert.deepEqual(load(JSON.stringify({ "apps:ghostty": m, a: null, b: { ...m, last: "1" }, c: 4 })), { "apps:ghostty": m })
})
