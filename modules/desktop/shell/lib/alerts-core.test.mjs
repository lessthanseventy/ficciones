// node --test lib/alerts-core.test.mjs (mise shell:test): the pure half of lib/alerts.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { showing, ofLevel, request, putsAway } from "./alerts-core.ts"

const alert = (key, level, actions = []) =>
  ({ key, level, kind: "k", title: key, body: null, at: "2026-10-08T00:00:00Z", thread_id: 198, link: null, actions })

test("an ask's answers are calls on the operator API, each with its own body", () => {
  const yes = { label: "Yes", method: "POST", path: "/api/office/asks/7", body: { key: "yes" } }
  assert.deepEqual(request(yes), { method: "POST", path: "/api/office/asks/7", body: { key: "yes" } })
  assert.deepEqual(request({ label: "Go", path: "/api/x" }), { method: "POST", path: "/api/x", body: {} })
})

test("a typed answer fills the action's input field", () => {
  const reply = { label: "Reply…", path: "/api/office/asks/7", body: { key: "other" }, input: "text" }
  assert.deepEqual(request(reply, "hi").body, { key: "other", text: "hi" })
})

test("a link or a doc makes no call", () => {
  assert.equal(request({ label: "Join", open: "https://meet" }), null)
  assert.equal(request({ label: "Read it", read: "/api/docs/1" }), null)
})

test("info is its own level, never sticky", () => {
  const as = [alert("ask:1", "decision"), alert("seated:2", "info"), alert("verify:3", "sticky")]
  assert.deepEqual(ofLevel(as, "info").map((a) => a.key), ["seated:2"])
  assert.deepEqual(ofLevel(as, "sticky").map((a) => a.key), ["verify:3"])
})

test("a dismissed key stays down, so an info toast shows once", () => {
  const as = [alert("seated:2", "info"), alert("seated:3", "info")]
  assert.deepEqual(showing(as, { dismissed: ["seated:2"], snoozed: {} }, 100).map((a) => a.key), ["seated:3"])
})

test("a snooze hides an alert until it runs out", () => {
  const as = [alert("meeting:1", "alarm")]
  assert.equal(showing(as, { dismissed: [], snoozed: { "meeting:1": 200 } }, 100).length, 0)
  assert.equal(showing(as, { dismissed: [], snoozed: { "meeting:1": 200 } }, 201).length, 1)
})

test("an alert the server can put away offers that, not the desktop's own Dismiss", () => {
  const away = { label: "Put away", method: "POST", path: "/api/office/needs/dismiss", body: { key: "mention:1" } }
  assert.equal(putsAway(alert("mention:1", "sticky", [away])), true)
  assert.equal(putsAway(alert("verify_failed:1", "sticky", [{ label: "Run verify again", path: "/api/threads/1/verify" }])), false)
})
