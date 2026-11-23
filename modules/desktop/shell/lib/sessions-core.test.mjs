// node --test lib/sessions-core.test.mjs (mise shell:test): the pure half of lib/sessions.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { parse, metered, alive, isCrew, mine, nextUp, chimes, arenaTarget, inboxArgs, findArena, waiting } from "./sessions-core.ts"

const s = (id, state, extra = {}) => ({ id, state, since: 1000, at: 1000, cwd: `/p/${id}`, repo: id, socket: "/tmp/tmux-1000/default", pane: `%${id.length}`, said: null, doing: null, ...extra })

test("a record parses, and anything else is dropped", () => {
  assert.deepEqual(parse(JSON.stringify(s("menard", "working"))), s("menard", "working"))
  assert.equal(parse("{half"), null)
  assert.equal(parse(JSON.stringify({ id: "x", state: "asleep" })), null)
})

test("the statusline's meter joins its record; a bad one is left out", () => {
  assert.deepEqual(metered(s("a", "working"), '{"ctx":41,"model":"Opus 5.5"}'), s("a", "working", { ctx: 41, model: "Opus 5.5" }))
  assert.deepEqual(metered(s("a", "working"), "{half"), s("a", "working"))
  assert.deepEqual(metered(s("a", "working"), null), s("a", "working"))
})

test("a record whose tmux pane is gone is stale; one outside tmux is, once a day has passed without a word", () => {
  const live = new Set(["/tmp/tmux-1000/default %6"])
  assert.equal(alive(s("menard", "done"), live, 1000), true)
  assert.equal(alive(s("ficciones", "done"), live, 1000), false)
  assert.equal(alive(s("solo", "done", { socket: "", pane: "", at: 1000 }), live, 1000 + 3600), true)
  assert.equal(alive(s("solo", "done", { socket: "", pane: "", at: 1000 }), live, 1000 + 86400), false)
})

test("the crew is any session on a tlon workspace's tmux server", () => {
  assert.equal(isCrew(s("a", "working", { socket: "/tmp/tmux-1000/tlon-workspace-3" })), true)
  assert.equal(isCrew(s("a", "working")), false)
})

test("yours come most pressing first: waiting, done, then at work", () => {
  const all = [s("b", "working"), s("crew", "waiting", { socket: "/tmp/tmux-1000/tlon-workspace-1" }), s("c", "done"), s("a", "waiting")]
  assert.deepEqual(mine(all).map((x) => x.id), ["a", "c", "b"])
  assert.equal(nextUp(all).id, "a")
  assert.equal(nextUp([]), null)
})


test("a session that starts waiting rings; a long turn that lands chimes; a short one is quiet", () => {
  const before = new Map([["a", s("a", "working", { since: 0 })], ["b", s("b", "working", { since: 950 })]])
  assert.deepEqual(chimes(before, [s("a", "waiting")], 1000), ["decision"])
  assert.deepEqual(chimes(before, [s("a", "done")], 1000), ["landing"])
  assert.deepEqual(chimes(before, [s("b", "done")], 1000), [])
  assert.deepEqual(chimes(new Map([["a", s("a", "waiting")]]), [s("a", "waiting")], 1000), [])
  assert.deepEqual(chimes(new Map(), [s("new", "done")], 1000), [])
})


test("arena is reached by its socket's name", () => {
  assert.deepEqual(arenaTarget(s("a", "done")), ["-L", "default"])
  assert.deepEqual(arenaTarget(s("a", "done", { socket: "/tmp/tmux-1000/tlon-workspace-2" })), ["-L", "tlon-workspace-2"])
})


test("arena's inbox opens on the board's own tmux server", () => {
  assert.deepEqual(inboxArgs(null), ["inbox"])
  assert.deepEqual(inboxArgs("/tmp/tmux-1000/tlon-workspace-2"), ["-L", "tlon-workspace-2", "inbox"])
})

const card = (id, pane, extra = {}) => ({ id, status: "doing", title: `ticket ${id}`, repo: "r", claimed_by: pane, ask: null, ...extra })
const ask = { id: 1, question: "ship it?", options: ["yes", "no"] }


test("what waits on you is the open asks, then the sessions waiting on an answer", () => {
  const all = [s("busy", "working"), s("stuck", "waiting", { doing: "Bash rm -rf" }), s("quiet", "waiting")]
  assert.deepEqual(waiting(all, [card(8, "%5", { ask })]), ["#8 asks: ship it?", "quiet waits", "stuck waits: Bash rm -rf"])
  assert.deepEqual(waiting([s("busy", "working")], []), [])
})

test("arena's window is found by its title on Ghostty's own class, or the class it was started with", () => {
  const term = { class: "com.mitchellh.ghostty", title: "zsh", address: "0x1" }
  const arena = { class: "com.mitchellh.ghostty", title: "arena", address: "0x2" }
  assert.equal(findArena([term, { class: "firefox", title: "arena" }, arena]), arena)
  const own = { class: "com.ghostty.arena", title: "arena", address: "0x3" }
  assert.equal(findArena([own]), own)
  assert.equal(findArena([term]), undefined)
})

