// node --test lib/poll-core.test.mjs (mise shell:test): a poll whose read fails keeps its value.
import { test, mock } from "node:test"
import assert from "node:assert/strict"
import { kept } from "./poll-core.ts"

test("a read that works passes through, sync or async", async () => {
  assert.equal(kept((p) => p + 1)(1), 2)
  assert.equal(await kept(async (p) => p + 1)(1), 2)
})

test("a throw or a rejection is logged and the value stays", async () => {
  const log = mock.method(console, "error", () => {})
  assert.equal(kept(() => { throw new Error("x") })(7), 7)
  assert.equal(await kept(async () => { throw new Error("x") })(7), 7)
  assert.equal(log.mock.callCount(), 2)
})
