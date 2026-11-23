// node --test lib/orchestrator-core.test.mjs (mise shell:test): the bar's orchestrator cell from a fake session record and board.
import { test } from "node:test"
import assert from "node:assert/strict"
import { cell, followTold, yourMove } from "./orchestrator-core.ts"

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
  assert.equal(cell(b, session("working"), null).text, "▲ 3 · orchestrator: working")
  assert.equal(cell(b, session("done"), null).text, "▲ 3 · orchestrator: idle")
  assert.equal(cell(b, null, null).text, "▲ 3 · orchestrator: idle")
  const waits = cell(b, session("waiting"), null)
  assert.equal(waits.text, "▲ 3 · orchestrator: waits on you")
  assert.equal(waits.attention, true)
  assert.equal(cell(b, session("working"), null).attention, false)
})

test("restarting is on and not running; off is kept off and not running", () => {
  assert.equal(cell(board([], { orchestrator: { on: true, running: false } }), null, null).text, "▲ 0 · orchestrator: restarting")
  assert.equal(cell(board([], { orchestrator: { on: false, running: false } }), null, null).text, "▲ 0 · orchestrator: off")
  assert.equal(cell(null, null, null).text, "▲ 0 · orchestrator: restarting")
})

test("▲ 0 is dim and keeps its place, a count is not", () => {
  assert.equal(cell(board(), session("done"), null).dim, true)
  assert.equal(cell(board([], { proposals: 1 }), session("done"), null).dim, false)
})

test("after a tell the cell says on it, then answered when a turn lands after it", () => {
  const told = { at: 200, phase: "on it" }
  assert.equal(cell(board(), session("done", 150), told).text, "▲ 0 · orchestrator: on it")
  assert.deepEqual(followTold(told, session("done", 150)), told)
  assert.deepEqual(followTold(told, session("working", 210)), told)
  const answered = followTold(told, session("done", 260))
  assert.equal(answered.phase, "answered")
  assert.equal(cell(board(), session("done", 260), answered).text, "▲ 0 · orchestrator: answered")
  assert.equal(followTold(null, session("done", 260)), null)
})
