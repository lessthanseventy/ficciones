// node --test lib/settings-core.test.mjs (mise shell:test): the pure half of lib/settings.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { load, dump, parseCli } from "./settings-core.ts"

const D = { "a.on": true, "a.n": 90, "a.s": "random", "a.list": [] }

test("no file reads as the defaults", () => {
  assert.deepEqual(load(D, null), { values: D, extra: {}, error: null })
})

test("known keys of the right type are taken; a wrong type keeps the default", () => {
  const { values } = load(D, JSON.stringify({ "a.on": false, "a.n": "fast", "a.list": ["x", 3, "y"] }))
  assert.deepEqual(values, { "a.on": false, "a.n": 90, "a.s": "random", "a.list": ["x", "y"] })
})

test("unknown keys are kept and written back", () => {
  const { values, extra } = load(D, JSON.stringify({ "a.n": 30, "later.key": 1 }))
  assert.deepEqual(extra, { "later.key": 1 })
  assert.deepEqual(JSON.parse(dump(values, extra)), { "later.key": 1, ...D, "a.n": 30 })
})

test("a malformed file reads as the defaults and says why", () => {
  const r = load(D, "{ nope")
  assert.deepEqual(r.values, D)
  assert.match(r.error ?? "", /JSON/)
  assert.deepEqual(load(D, "[1,2]").values, D)
})

test("the CLI's text becomes the default's type", () => {
  assert.equal(parseCli(true, "off"), false)
  assert.equal(parseCli(false, "on"), true)
  assert.equal(parseCli(90, "45"), 45)
  assert.equal(parseCli("random", "boids"), "boids")
  assert.deepEqual(parseCli([], "glplanet, flurry"), ["glplanet", "flurry"])
  assert.deepEqual(parseCli([], ""), [])
  assert.ok(parseCli(true, "maybe") instanceof Error)
  assert.ok(parseCli(90, "fast") instanceof Error)
})

test("the numeric tuning settings load as numbers and fall back on a wrong type", () => {
  const T = { "backdrop.smoothHz": 15, "sound.vizBars": 24, "feel.hoverDwellMs": 500 }
  assert.deepEqual(load(T, JSON.stringify({ "backdrop.smoothHz": 30, "sound.vizBars": 12 })).values, { "backdrop.smoothHz": 30, "sound.vizBars": 12, "feel.hoverDwellMs": 500 })
  assert.deepEqual(load(T, JSON.stringify({ "backdrop.smoothHz": "fast", "sound.vizBars": null })).values, T)
})
