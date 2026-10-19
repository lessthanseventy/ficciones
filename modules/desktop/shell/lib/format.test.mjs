// node --test lib/format.test.mjs (mise shell:test): the shell's shared text formats.
import { test } from "node:test"
import assert from "node:assert/strict"
import { hhmm, duration } from "./format.ts"

test("hhmm is 24 h, zero-padded, from a timestamp, an ISO string or a Date", () => {
  const d = new Date(2026, 0, 2, 9, 5)
  assert.equal(hhmm(d), "09:05")
  assert.equal(hhmm(d.getTime()), "09:05")
  assert.equal(hhmm(d.toISOString()), "09:05")
  assert.equal(hhmm(new Date(2026, 0, 2, 23, 59)), "23:59")
})

test("hhmm of a non-date is empty", () => {
  assert.equal(hhmm("not a date"), "")
  assert.equal(hhmm(NaN), "")
})

test("duration, clock style, is a countdown", () => {
  assert.equal(duration(0), "0:00")
  assert.equal(duration(245), "4:05")
  assert.equal(duration(3723), "1:02:03")
  assert.equal(duration(-5), "0:00")
  assert.equal(duration(59.6), "1:00")
})

test("duration, words style, is for a setting's value", () => {
  assert.equal(duration(45, "words"), "45 s")
  assert.equal(duration(125, "words"), "2 m 5 s")
  assert.equal(duration(180, "words"), "3 min")
})
