// node --test lib/board-core.test.mjs (mise shell:test): the pure half of lib/board.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { parse, asking } from "./board-core.ts"

const card = (id, status, extra = {}) => ({ id, status, title: `ticket ${id}`, repo: "ficciones", claimed_by: null, ask: null, ...extra })
const board = (tickets, extra = {}) => ({ tickets, auto: { on: true, cap: 2, working: 1 }, hold: false, socket: null, needsYou: [], orchestrator: { on: true, running: true }, ...extra })
const ask ={ id: 4, question: "which way out?", options: ["vendor", "remove"] }

test("a board parses, and anything else is dropped", () => {
  const b = board([card(1, "doing")])
  assert.deepEqual(parse(JSON.stringify({ ...b, backlog: [], needs_you: [] })), b)
  assert.equal(parse(JSON.stringify({ ...b, socket: "/tmp/tmux-1000/default" })).socket, "/tmp/tmux-1000/default")
  assert.equal(parse("{half"), null)
  assert.equal(parse(JSON.stringify({ tickets: [] })), null)
})

test("the asking cards are those with a question open, whatever their column", () => {
  const b = board([card(1, "doing"), card(2, "done", { ask }), card(3, "todo", { ask })])
  assert.deepEqual(asking(b).map((t) => t.id), [2, 3])
  assert.deepEqual(asking(null), [])
})

test("an item with no action list still counts, with no actions", () => {
  const raw = [{ id: "a", kind: "ask", text: "x" }, { id: "b", kind: "ask", text: "y", actions: [{ key: "k", label: "L", argv: ["go"] }] }]
  const b = parse(JSON.stringify({ tickets: [], auto: { on: true }, needs_you: raw }))
  assert.deepEqual(b.needsYou.map((i) => i.actions.length), [0, 1])
})
