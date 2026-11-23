// node --test lib/orchestrator-core.test.mjs (mise shell:test): the bar's orchestrator cell from a fake session record and board.
import { test } from "node:test"
import assert from "node:assert/strict"
import { cell, yourMove } from "./orchestrator-core.ts"

const card = (id, extra = {}) => ({ id, status: "todo", title: `t${id}`, repo: "x", claimed_by: null, ask: null, stage: null, blocked_by: [], ...extra })
const ask = { id: 1, question: "q", options: [] }
const board = (tickets = [], extra = {}) => ({ tickets, auto: { on: true, cap: 2, working: 0 }, hold: false, socket: null, proposals: 0, orchestrator: { on: true, running: true }, ...extra })
const session = (state, since = 100) => ({ id: "o", state, since, at: since, cwd: "", repo: "orchestrator", socket: "", pane: "%1", said: null, doing: null })

test("N counts asks, proposals and free send-backs only", () => {
  const free = card(1, { status: "doing", stage: "failed" })
  const held = card(2, { status: "doing", stage: "failed", claimed_by: "%9" })
  const blocked = card(3, { status: "doing", stage: "failed", blocked_by: [7] })
  assert.equal(yourMove(board([free, held, blocked, card(4, { ask }), card(5)], { proposals: 2 })), 4)
  assert.equal(yourMove(null), 0)
})

test("the cell says each state the session record gives", () => {
  const b = board([card(1, { ask })], { proposals: 2 })
  assert.equal(cell(b, session("working")).text, "▲ 3 · orchestrator: working")
  assert.equal(cell(b, session("done")).text, "▲ 3 · orchestrator: idle")
  assert.equal(cell(b, null).text, "▲ 3 · orchestrator: idle")
  const waits = cell(b, session("waiting"))
  assert.equal(waits.text, "▲ 3 · orchestrator: waits on you")
  assert.equal(waits.attention, true)
  assert.equal(cell(b, session("working")).attention, false)
})

test("restarting is on and not running; off is kept off and not running", () => {
  assert.equal(cell(board([], { orchestrator: { on: true, running: false } }), null).text, "▲ 0 · orchestrator: restarting")
  assert.equal(cell(board([], { orchestrator: { on: false, running: false } }), null).text, "▲ 0 · orchestrator: off")
  assert.equal(cell(null, null).text, "▲ 0 · orchestrator: restarting")
})

test("▲ 0 is dim and keeps its place, a count is not", () => {
  assert.equal(cell(board(), session("done")).dim, true)
  assert.equal(cell(board([], { proposals: 1 }), session("done")).dim, false)
})

