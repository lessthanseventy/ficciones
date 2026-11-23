// node --test lib/needs-core.test.mjs (mise shell:test): which notices a needs_you list raises and closes.
import { test } from "node:test"
import assert from "node:assert/strict"
import { plan, noticeArgv, chosen, parseRaised } from "./needs-core.ts"
import { items } from "./board-core.ts"
import { itemArgs } from "./sessions-core.ts"

const proposal = { id: "proposal:3", kind: "proposal", ticket: 9, repo: "x", text: "P3 start #9", actions: [{ key: "⏎", label: "go", argv: ["babylon", "go", "3"] }, { key: "x", label: "no", argv: ["babylon", "no", "3"] }] }
const words = { id: "ask:5", kind: "ask", ticket: 7, repo: "x", text: "#7 asks: q", actions: [{ key: "1", label: "a", argv: ["babylon", "answer", "5", "1"] }, { key: "c", label: "in words", argv: null }] }

test("items keeps what is well formed and drops the rest", () => {
  assert.deepEqual(items([proposal, { id: 4 }, null, { ...words, ticket: "7", actions: [{ label: "x", argv: ["a", 1] }, {}] }]).map((i) => i.id), ["proposal:3", "ask:5"])
  assert.equal(items([{ ...words, ticket: undefined }])[0].ticket, null)
  assert.deepEqual(items(undefined), [])
})

test("a new id is raised once, a gone id is closed", () => {
  const first = plan(new Set(), [proposal, words], false)
  assert.deepEqual(first.raise.map((i) => i.id), ["proposal:3", "ask:5"])
  assert.deepEqual(plan(new Set(["proposal:3", "ask:5"]), [proposal, words], false), { raise: [], seen: [], close: [] })
  assert.deepEqual(plan(new Set(["proposal:3", "ask:5"]), [words], false).close, ["proposal:3"])
})

test("parseRaised keeps string ids and survives a corrupt file", () => {
  assert.deepEqual(parseRaised('["proposal:3","ask:5"]'), ["proposal:3", "ask:5"])
  assert.deepEqual(parseRaised('["a",3,null,{"x":1},"b"]'), ["a", "b"])
  for (const bad of ["", "{", "null", '{"a":1}', '"ask:5"', "7"]) assert.deepEqual(parseRaised(bad), [])
})

test("ids loaded after a restart are not raised again", () => {
  const loaded = new Set(parseRaised('["proposal:3","ask:5"]'))
  assert.deepEqual(plan(loaded, [proposal, words], false), { raise: [], seen: [], close: [] })
  assert.deepEqual(plan(loaded, [words], false).close, ["proposal:3"])
})

test("with arena in front nothing is raised, and what arrived is marked seen", () => {
  const p = plan(new Set(), [proposal], true)
  assert.deepEqual(p.raise, [])
  assert.deepEqual(p.seen, ["proposal:3"])
})

test("the notice carries the item's runnable actions; words and picks stay in arena", () => {
  const argv = noticeArgv(words, 2)
  assert.deepEqual(argv.slice(-2), ["▲ 2 need you", "#7 asks: q"])
  assert.deepEqual(argv.filter((_, k) => argv[k - 1] === "-A"), ["default=open", "a0=a"])
  assert.deepEqual(chosen(words, "a0\n"), ["babylon", "answer", "5", "1"])
  assert.equal(chosen(words, "default"), null)
  assert.equal(chosen(words, "a1"), null)
})

test("open goes to the item's ticket, or to the inbox when it has none", () => {
  assert.deepEqual(itemArgs(proposal.ticket, null), ["board", "9"])
  assert.deepEqual(itemArgs(null, "/tmp/tmux-1000/default"), ["-L", "default", "inbox"])
})
