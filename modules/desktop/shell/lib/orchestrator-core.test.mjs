// node --test lib/orchestrator-core.test.mjs (mise shell:test): the bar's orchestrator cell from a fake session record and board.
import { test } from "node:test"
import assert from "node:assert/strict"
import { cell, followTold } from "./orchestrator-core.ts"
import { parse } from "./board-core.ts"

const card = (id, extra = {}) => ({ id, status: "todo", title: `t${id}`, repo: "x", claimed_by: null, ask: null, stage: null, blocked_by: [], ...extra })
const ask = { id: 1, question: "q", options: [] }
const needs = (n) => Array.from({ length: n }, (_, k) => ({ id: `ask:${k}`, kind: "ask", ticket: k, repo: "x", text: "t", actions: [] }))
const board = (tickets = [], extra = {}) => ({ tickets, auto: { on: true, cap: 2, working: 0 }, hold: false, socket: null, needsYou: [], orchestrator: { on: true, running: true }, ...extra })
const session = (state, since = 100) => ({ id: "o", state, since, at: since, cwd: "", repo: "orchestrator", socket: "", pane: "%1", said: null, doing: null })

test("N is the length of needs_you, whatever the tickets say", () => {
  const raw = (extra) => JSON.stringify({ tickets: [card(1, { ask })], auto: { on: true, cap: 2, working: 0 }, orchestrator: { on: true, running: true }, ...extra })
  assert.equal(cell(parse(raw({ needs_you: [{ id: "a", text: "t", actions: [] }, { id: "b", text: "t", actions: [] }] })), null).text, "▲ 2 · 0/2 · orchestrator: idle")
  assert.equal(cell(parse(raw({})), null).text, "▲ 0 · 0/2 · orchestrator: idle")
  assert.equal(cell(null, null).text, "▲ 0 · orchestrator: restarting")
})

test("the cell says each state the session record gives", () => {
  const b = board([card(1, { ask })], { needsYou: needs(3) })
  assert.equal(cell(b, session("working")).text, "▲ 3 · 0/2 · orchestrator: working")
  assert.equal(cell(b, session("done")).text, "▲ 3 · 0/2 · orchestrator: idle")
  assert.equal(cell(b, null).text, "▲ 3 · 0/2 · orchestrator: idle")
  const waits = cell(b, session("waiting"))
  assert.equal(waits.text, "▲ 3 · 0/2 · orchestrator: waits on you")
  assert.equal(waits.attention, true)
  const stalled = cell(b, session("stalled"))
  assert.equal(stalled.text, "▲ 3 · 0/2 · orchestrator: stalled")
  assert.equal(stalled.attention, true)
  assert.equal(cell(b, session("working")).attention, false)
})

test("restarting is on and not running; off is kept off and not running", () => {
  assert.equal(cell(board([], { orchestrator: { on: true, running: false } }), null).text, "▲ 0 · 0/2 · orchestrator: restarting")
  assert.equal(cell(board([], { orchestrator: { on: false, running: false } }), null).text, "▲ 0 · 0/2 · orchestrator: off")
  assert.equal(cell(null, null).text, "▲ 0 · orchestrator: restarting")
})

test("▲ 0 is dim and keeps its place, a count is not", () => {
  assert.equal(cell(board(), session("done")).dim, true)
  assert.equal(cell(board([], { needsYou: needs(1) }), session("done")).dim, false)
})

test("after a tell the cell says on it, whatever the session says, until its turn lands", () => {
  const sent = { at: 200, phase: "sent" }
  assert.equal(cell(board(), session("done", 150), sent).text, "▲ 0 · 0/2 · orchestrator: on it")
  assert.equal(cell(board(), session("waiting", 150), sent).attention, false)
})

test("on it: a turn that starts after the tell, then answered when it ends", () => {
  const sent = { at: 200, phase: "sent" }
  assert.deepEqual(followTold(sent, session("done", 150)), sent)
  assert.deepEqual(followTold(sent, session("working", 150)), sent)
  const onIt = followTold(sent, session("working", 210))
  assert.equal(onIt.phase, "on it")
  assert.deepEqual(followTold(onIt, session("working", 210)), onIt)
  const answered = followTold(onIt, session("done", 260))
  assert.equal(answered.phase, "answered")
  assert.equal(cell(board(), session("done", 260), answered).text, "▲ 0 · 0/2 · orchestrator: answered")
  assert.deepEqual(followTold(answered, session("working", 300)), answered)
})

test("a held line: the turn running at the tell ending is not the answer, the next turn is", () => {
  const sent = { at: 200, phase: "sent" }
  assert.deepEqual(followTold(sent, session("working", 150)), sent)
  assert.deepEqual(followTold(sent, session("done", 260)), sent)
  assert.equal(followTold(sent, session("working", 270)).phase, "on it")
})

test("no told, no session: nothing moves", () => {
  assert.equal(followTold(null, session("done", 260)), null)
  assert.deepEqual(followTold({ at: 1, phase: "sent" }, null), { at: 1, phase: "sent" })
})

test("the tell is stamped before babylon runs, so the turn it starts is at or after it, even in the same second", () => {
  const sent = { at: 200, phase: "sent" }
  assert.equal(followTold(sent, session("working", 200)).phase, "on it")
  assert.deepEqual(followTold(sent, session("working", 199)), sent)
})

test("a turn already running when the told is set is seen at once, and its end answers", () => {
  // the order of events in Tell.tsx: stamp, babylon runs, the working record lands, then noteTold evaluates against it
  const at = 200
  const running = session("working", 201)
  const told = followTold({ at, phase: "sent" }, running)
  assert.equal(told.phase, "on it")
  assert.equal(followTold(told, session("done", 230)).phase, "answered")
})

const withAuto = (auto, extra = {}) => board([], { auto: { on: true, cap: 6, working: 5, ...auto }, needsYou: needs(2), ...extra })

test("on: needs-you, then working/cap, then the state", () => {
  assert.equal(cell(withAuto({}), session("done")).text, "▲ 2 · 5/6 · orchestrator: idle")
})

test("auto off reads auto off in place of working/cap", () => {
  assert.equal(cell(withAuto({ on: false }), session("done")).text, "▲ 2 · auto off · orchestrator: idle")
})

test("hold adds held as its own piece, for the warning colour", () => {
  const c = cell(withAuto({}, { hold: true }), session("done"))
  assert.deepEqual([c.text, c.held, c.paused], ["▲ 2 · 5/6 · orchestrator: idle", " · held", ""])
  assert.equal(cell(withAuto({}), session("done")).held, "")
})

test("a repo at cap 0 is paused; several are joined; a repo above 0 is not", () => {
  assert.equal(cell(withAuto({ repo_caps: { babylon: 0, arena: 1 } }), session("done")).paused, " · babylon paused")
  assert.equal(cell(withAuto({ repo_caps: { babylon: 0, menard: 0 } }), session("done")).paused, " · babylon, menard paused")
  assert.equal(cell(withAuto({ repo_caps: { arena: 1 } }), session("done")).paused, "")
})

test("narrow: the paused part goes first, then the orchestrator state, never the count", () => {
  const b = withAuto({ repo_caps: { babylon: 0 } }, { hold: true })
  const whole = "▲ 2 · 5/6 · orchestrator: idle · held · babylon paused"
  const at = (w) => { const c = cell(b, session("done"), null, w); return c.text + c.held + c.paused }
  assert.equal(at(whole.length), whole)
  assert.equal(at(whole.length - 1), "▲ 2 · 5/6 · orchestrator: idle · held")
  assert.equal(at("▲ 2 · 5/6 · orchestrator: idle · held".length - 1), "▲ 2 · 5/6 · held")
  assert.equal(at(1), "▲ 2 · 5/6 · held")
})

test("a board with no repo_caps has no paused repos", () => {
  assert.equal(cell(board(), session("done")).paused, "")
})
