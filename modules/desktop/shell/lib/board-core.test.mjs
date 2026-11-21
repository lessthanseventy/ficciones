// node --test lib/board-core.test.mjs (mise shell:test): the pure half of lib/board.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { parse, asking, held, boardLine } from "./board-core.ts"

const card = (id, status, extra = {}) => ({ id, status, title: `ticket ${id}`, repo: "ficciones", claimed_by: null, ask: null, ...extra })
const board = (tickets, extra = {}) => ({ tickets, auto: { on: true, cap: 2, working: 1 }, hold: false, ...extra })
const ask = { id: 4, question: "which way out?", options: ["vendor", "remove"] }

test("a board parses, and anything else is dropped", () => {
  const b = board([card(1, "doing")])
  assert.deepEqual(parse(JSON.stringify({ ...b, backlog: [], orchestrator: { on: true, running: true } })), b)
  assert.equal(parse("{half"), null)
  assert.equal(parse(JSON.stringify({ tickets: [] })), null)
})

test("the asking cards are those with a question open, whatever their column", () => {
  const b = board([card(1, "doing"), card(2, "done", { ask }), card(3, "todo", { ask })])
  assert.deepEqual(asking(b).map((t) => t.id), [2, 3])
  assert.deepEqual(asking(null), [])
})

test("a pane holds the ticket it works on before one it has handed in, and never a done one", () => {
  const b = board([card(1, "review", { claimed_by: "%7" }), card(2, "doing", { claimed_by: "%7" }), card(3, "done", { claimed_by: "%9" })])
  assert.equal(held(b, "%7").id, 2)
  assert.equal(held(b, "%9"), null)
  assert.equal(held(b, ""), null)
  assert.equal(held(null, "%7"), null)
})

test("the board line counts doing, review and asks, then auto and hold", () => {
  const b = board([card(1, "doing"), card(2, "doing"), card(3, "review", { ask }), card(4, "todo")])
  assert.equal(boardLine(b), "doing 2 · review 1 · asks 1 · auto 1/2 · hold off")
  assert.equal(boardLine(board([], { auto: { on: false, cap: 2, working: 0 }, hold: true })), "doing 0 · review 0 · asks 0 · auto off · hold on")
  assert.equal(boardLine(null), "no board")
})
